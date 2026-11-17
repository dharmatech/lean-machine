-- Builds the `desktop` executable from the Lean code and shim.c. Needs Lean
-- (elan), Cairo and SDL3's shared library; SDL3's headers aren't needed.
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

/-- The modules under LeanMachine/, which Main.lean imports. -/
lean_lib LeanMachine where
  globs := #[.submodules `LeanMachine]

@[default_target]
lean_exe desktop where
  root := `Main
  moreLinkObjs := #[shim]
  -- Lean links against its own C library. Name each system library by its
  -- full path: an `-L` to their directory pulls in the system's start files
  -- and the link fails.
  moreLinkArgs := run_io do
    let lib := (← pkgConfig #["--variable=libdir", "cairo"])[0]!
    return #[s!"{lib}/libcairo.so.2", s!"{lib}/libSDL3.so.0",
             "-Wl,--allow-shlib-undefined"]
