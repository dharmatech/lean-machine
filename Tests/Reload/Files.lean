import Tests.Reload.Kit

/-! # `--test`: files reloaded in the desktop's Lean

Each app's file reloaded three times, files that can't be, Boids'
compiled simulation in the REPL, and a file with an error
(docs/design/reloading/README.md). -/

namespace LeanMachine.Tests

-- Each app's file, reloaded in the desktop's Lean three times; files
-- that can't be; and Clock.lean with an error. The apps the reloads
-- made, for `reloadOnDesktop` and `reloadCosts`.
def reloadFiles (svc : Services) : IO (List (Lean.Name × App)) := do
  IO.println "each app's file, reloaded in the desktop's Lean three times:"
  let mut made : List (Lean.Name × App) := []
  for file in ["Clock", "Placeholder", "Repl", "Editor", "Boids"] do
    let path := s!"LeanMachine/Apps/{file}.lean"
    let src ← IO.FS.readFile (projectRoot / path)
    let mut times := #[]
    let mut said := ""
    let mut apps := []
    for _ in [0:3] do
      let (o, a, t) ← reloadNow svc path src
      times := times.push t; said := o.show; apps := a
    made := made ++ apps
    IO.println s!"  {file}.lean: {times} ms; {said}"
  IO.println "files it can't reload:"
  for path in ["LeanMachine/Desktop.lean", "Main.lean", "LeanMachine/Apps/Boids/Flock.lean"] do
    let (o, _, _) ← reloadNow svc path (← IO.FS.readFile (projectRoot / path))
    IO.println s!"  {path}: {o.show}"
  -- Boids' simulation is there, compiled, for the REPL too.
  let flockLine := "(Boids.Flock.demo.stepOn {} 100 100).map (·.position.x)"
  IO.println s!"  in the REPL, {flockLine}: {(← svc.eval flockLine none (← IO.CancelToken.new)).show}"
  let clockSrc ← IO.FS.readFile (projectRoot / "LeanMachine/Apps/Clock.lean")
  let (o, apps, _) ← reloadNow svc "Clock.lean" (clockSrc.replace "t.digits]" "t.digit]")
  IO.println s!"  Clock.lean with `t.digit`: {o.show}; {apps.length} apps"
  return made

end LeanMachine.Tests
