import Tests.Reload.Files
import Tests.Reload.Editor
import Tests.Reload.Desktop
import Tests.Reload.Boids
import Tests.Reload.Costs
import Tests.Reload.Memory

/-! # `--test`: reloading apps

Each phase is a module of Tests/Reload/, with what they share in
Tests/Reload/Kit.lean (docs/design/reloading/README.md). -/

namespace LeanMachine.Tests

-- Reloading apps from their files: each app's file in the desktop's
-- Lean, files that can't be reloaded, an editor alone, then the desktop
-- with real runs: Clock.lean edited and reloaded into the open clock,
-- undone, an error, Editor.lean reloaded from an editor, a stop, a new
-- app; Boids.lean edited and reloaded into an open flock, over the
-- compiled simulation, whose files can't be reloaded; then what reloaded
-- code costs to run, and memory over many reloads.
def testReload (c : Canvas) (svc : Services) : IO Unit := do
  let made ← reloadFiles svc
  reloadInEditor svc
  let (d, runs) ← reloadOnDesktop c svc made
  reloadBoids c svc
  reloadCosts c svc made
  reloadMemory svc d runs

end LeanMachine.Tests
