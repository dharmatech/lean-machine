import Tests.Desktop
import Tests.Resize
import Tests.Maximize
import Tests.Minimize
import Tests.Screen
import Tests.Frames
import Tests.Boids
import Tests.Slider
import Tests.Highlight
import Tests.Editor
import Tests.Paste
import Tests.Select
import Tests.Copy
import Tests.ReplCopy
import Tests.Reload
import Tests.Runs
import Tests.Masking

/-! # `--test`: every test, in turn

`all` runs the test in each module of Tests/, in the order `--test` has
always run them; what they share is in Tests/Kit.lean, and how they
print what they find in Tests/Show.lean (docs/design/testing.md). -/

namespace LeanMachine.Tests

-- Every test, in turn. What they draw goes to `testOut`.
def all (c : Canvas) (svc : Services) : IO Unit := do
  IO.FS.createDirAll testOut
  test c svc
  testResize c svc
  testMaximize c svc
  testMinimize c
  testScreen
  testFrames c svc
  testBoids c
  testSlider c svc
  testLean c svc
  testEditor c svc
  testPaste c svc
  testSelect c svc
  testCopy c svc
  testReplCopy c svc
  testReload c svc
  testRuns c svc
  testMasking

end LeanMachine.Tests
