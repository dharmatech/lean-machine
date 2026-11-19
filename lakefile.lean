-- Builds the `desktop` executable from the Lean code, shim.c and runs.cpp.
-- Needs Lean (elan), Cairo, SDL3's shared library and a C++ compiler; SDL3's
-- headers aren't needed.
import Lake
open Lake DSL System

package "lean-machine"

/-- The words `pkg-config args` prints. -/
def pkgConfig (args : Array String) : IO (Array String) := do
  let out ← IO.Process.output { cmd := "pkg-config", args }
  if out.exitCode != 0 then
    throw <| IO.userError s!"pkg-config {args} failed: {out.stderr}"
  return (out.stdout.splitOn " ").toArray.map (·.trimAscii.toString)
    |>.filter (· != "")

/-- shim.c, compiled with the system's `cc`: the clang that comes with Lean
has no system headers such as `math.h`. -/
target shim pkg : FilePath := do
  let src ← inputTextFile (pkg.dir / "shim.c")
  let includes := #["-I", (← getLeanIncludeDir).toString] ++
    (← pkgConfig #["--cflags", "cairo"])
  buildO (pkg.buildDir / "c" / "shim.o") src includes #["-O2", "-fPIC"] "cc"
    getLeanTrace

/-- runs.cpp, the guard that stops a run, compiled with the system's `c++`.
It uses no C++ library, only exceptions, which Lean's own C++ runtime
handles when it links. -/
target runs pkg : FilePath := do
  let src ← inputTextFile (pkg.dir / "runs.cpp")
  buildO (pkg.buildDir / "c" / "runs.o") src
    #["-I", (← getLeanIncludeDir).toString] #["-O2", "-fPIC", "-std=c++17"] "c++"
    getLeanTrace

/-- The modules under LeanMachine/, which Main.lean imports. -/
lean_lib LeanMachine where
  globs := #[.submodules `LeanMachine]

/-- The tests `--test` runs, under Tests/, which Main.lean imports: a
library apart from `LeanMachine`, since nothing in it should import
them. -/
lean_lib Tests where
  globs := #[.submodules `Tests]

@[default_target]
lean_exe desktop where
  root := `Main
  -- The REPL evaluates Lean in this process: Lean's interpreter is linked
  -- in, and the symbols it calls are exported.
  supportInterpreter := true
  moreLinkObjs := #[shim, runs]
  -- Lean links against its own C library. Name each system library by its
  -- full path: an `-L` to their directory pulls in the system's start files
  -- and the link fails. The wrapped primitives go through runs.cpp first:
  -- every small allocation is a safepoint, a run isn't cut off between a
  -- ref's take and put or while it holds a mutex, and a sleep ends when its
  -- run is asked to stop.
  moreLinkArgs := run_io do
    let lib := (← pkgConfig #["--variable=libdir", "cairo"])[0]!
    let wrapped := #["lean_alloc_small_object_core", "lean_st_ref_take", "lean_st_ref_put",
      "lean_io_basemutex_lock", "lean_io_basemutex_try_lock", "lean_io_basemutex_unlock",
      "lean_io_baserecmutex_lock", "lean_io_baserecmutex_try_lock",
      "lean_io_baserecmutex_unlock", "lean_io_basesharedmutex_write",
      "lean_io_basesharedmutex_try_write", "lean_io_basesharedmutex_unlock_write",
      "lean_io_basesharedmutex_read", "lean_io_basesharedmutex_try_read",
      "lean_io_basesharedmutex_unlock_read", "lean_dbg_sleep"]
    return #[s!"{lib}/libcairo.so.2", s!"{lib}/libSDL3.so.0",
             "-Wl,--allow-shlib-undefined"] ++ wrapped.map (s!"-Wl,--wrap={·}")
