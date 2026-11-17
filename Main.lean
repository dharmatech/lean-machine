import LeanMachine.Host
import LeanMachine.View

-- A desktop as a value. `World.step` and `Desktop.view` are pure (in
-- LeanMachine/); the loop here is the only code that does I/O, and `render`
-- (LeanMachine/Host.lean) the only code that draws.

open LeanMachine

/-! ## The loop: the only I/O -/

-- Applies every waiting event, then draws once. `frames` stops it early
-- (for tests); the window's close button or Esc stops it any time.
partial def run (c : Canvas) (d : Desktop) (frames : Option Nat) : IO Unit := do
  if frames == some 0 then return
  let mut d := d
  let mut quit := false
  let mut raw ← Host.event 100
  while raw.get! 0 != 0 do
    match Event.decode raw with
    | some .quit => quit := true
    | some (.key k) => if k == keyEscape then quit := true else d := d.step (.key k)
    | some e => d := d.step e
    | none => pure ()
    raw ← Host.event 0
  if quit then return
  render c d.view
  Host.present c
  run c d (frames.map (· - 1))

-- The pure world, driven by a script of events instead of a person.
def test (c : Canvas) : IO Unit := do
  let grab := Event.press 300 (160 + 10)          -- Clock's title
  let script := [grab, .motion 700 500, .release 700 500,
                 .key keyN,                         -- a window at the pointer
                 .press (80 + 420 - 15) (70 + 14)]  -- REPL's close box
  let d := script.foldl Desktop.step start
  IO.println s!"after the script: {d.now.windows.map (·.title)}, \
    focus {d.now.focus}, {d.past.length} earlier worlds"
  let clock := d.now.windows.find? (·.title == "Clock")
  IO.println s!"Clock at {clock.map (·.x)} {clock.map (·.y)}; \
    in the start world still at {(start.now.windows.find? (·.title == "Clock")).map (·.x)}"
  render c d.view; c.savePng "after-script.png"
  let d := (d.step (.key keyU)).step (.key keyU)
  IO.println s!"after two undos: {d.now.windows.map (·.title)}"
  render c d.view; c.savePng "after-undo.png"

def main (args : List String) : IO Unit := do
  let c ← Canvas.new screenW.toUInt32 screenH.toUInt32
  match args with
  | ["--test"] => test c
  | ["--frames", n] =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c start n.toNat?
  | _ =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c start none
