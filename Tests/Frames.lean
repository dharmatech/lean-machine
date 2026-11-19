import Tests.Kit

/-! # `--test`: frames

A spinner, an app that animates: opened as a run in the REPL would
open it, minimized, undone, and made in the REPL itself, turned by
the frames it hears (docs/design/world/frames.md). -/

namespace LeanMachine.Tests

-- A hand that the frames it hears turn, once every π seconds, with the
-- last frame's time in its title.
def spinner : App :=
  App.asking "Spin" (0 : Nat) (fun _ e => match e with | .frame ms => some (ms, []) | _ => none)
    (fun ms w h =>
      let a := ms.toFloat / 500
      .line (w / 2) (h / 2) (w / 2 + 80 * a.cos) (h / 2 + 80 * a.sin) 4 0xf7768e)
    (titleOf := fun ms => s!"Spin {ms}") (animating := fun _ => true)

-- A spinner made in the REPL, as docs/explore/spinner.md types it.
def spinnerLines : List String :=
  ["def hand (ms : Nat) (w h : Float) : Picture := let a := ms.toFloat / 500; \
      .line (w / 2) (h / 2) (w / 2 + 80 * a.cos) (h / 2 + 80 * a.sin) 4 0xf7768e",
   "def hear : Nat → AppEvent → Option Nat | _, .frame ms => some ms | _, _ => none",
   "launch (App.of \"Spin\" 0 hear hand (animating := fun _ => true))"]

def testFrames (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "frames:"
  let start := steps start [.tick ⟨10, 8, 30⟩]
  let spin (d : Desktop) : String :=
    ((d.now.windows.find? (·.title.startsWith "Spin")).map (·.title)).getD "none"
  IO.println s!"  the start desktop animates: {start.now.animating}"
  -- A spinner, as a run in the REPL (window 1) would open it.
  let d := steps start [.launch 1 spinner, .frame 1000, .frame 1017]
  IO.println s!"  a spinner opened, focus on {focused d}: animates {d.now.animating}; \
    after frames at 1000 and 1017 ms: {spin d}; earlier worlds {d.past.length}, as before \
    {start.past.length}"
  render c d.view; shot c "frames.png"
  -- Minimized, it hears no frames, and the desktop doesn't animate.
  let dm := steps d [.key (.char 'h') ctrlShift, .frame 2000]
  IO.println s!"  minimized: animates {dm.now.animating}; after a frame at 2000 ms: {spin dm}"
  let db := steps dm [undoKey, .frame 3000]
  IO.println s!"  undone: animates {db.now.animating}; after a frame at 3000 ms: {spin db}"
  -- Made in the REPL: compiled there, and turned by the same frames.
  let (d, seen) ← typedInRepl svc start spinnerLines
  IO.println s!"  a spinner made in the REPL: {seen.map (·.showDone)}; windows \
    {d.now.windows.map (·.title)}; animates {d.now.animating}"
  render c (steps d [.frame 700]).view; shot c "frames-repl.png"

end LeanMachine.Tests
