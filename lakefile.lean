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

@[default_target]
lean_exe desktop where
  root := `Main
  -- The REPL evaluates Lean in this process: Lean's interpreter is linked
  -- in, and the symbols it calls are exported.
  supportInterpreter := true
  moreLinkObjs := #[shim, runs]
  -- Lean links against its own C library. Name each system library by its
  -- full path: an `-L` to their directory pulls in the system's start files
  -- and the link fails. Every small allocation in Lean code goes through
  -- runs.cpp's safepoint first.
  moreLinkArgs := run_io do
    let lib := (← pkgConfig #["--variable=libdir", "cairo"])[0]!
    return #[s!"{lib}/libcairo.so.2", s!"{lib}/libSDL3.so.0",
             "-Wl,--allow-shlib-undefined",
             "-Wl,--wrap=lean_alloc_small_object_core"]
