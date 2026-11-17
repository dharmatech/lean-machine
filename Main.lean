import LeanMachine.Host
import LeanMachine.View

-- A desktop as a value. `World.step` and `Desktop.view` are pure (in
-- LeanMachine/); the loop here is the only code that does I/O, and `render`
-- (LeanMachine/Host.lean) the only code that draws.

open LeanMachine

/-! ## The loop: the only I/O -/

-- Applies every waiting event and a tick with the time, then draws once.
-- `frames` stops it early (for tests); the window's close button or Esc
-- stops it any time.
partial def run (c : Canvas) (d : Desktop) (frames : Option Nat) : IO Unit := do
  if frames == some 0 then return
  let mut d := d
  let mut quit := false
  -- Waits for an event, but not past 100 ms or the start of the next
  -- second, so a clock turns over on time.
  let (_, msLeft) ← localTime
  let mut raw ← Host.event (min 100 (msLeft + 1)).toUInt32
  while raw.get! 0 != 0 do
    match Event.decode raw with
    | some .quit => quit := true
    -- Esc closes the menu if it's open, and quits if it isn't.
    | some (.key k) =>
      if k == keyEscape && d.now.menu.isNone then quit := true
      else d := d.step (.key k)
    | some e => d := d.step e
    | none => pure ()
    raw ← Host.event 0
  if quit then return
  let (t, _) ← localTime
  d := d.step (.tick t)
  render c d.view
  Host.present c
  run c d (frames.map (· - 1))

-- One of each kind of picture, for `--test`: lines, circles, text placed in
-- boxes, and a picture moved and cut to a box.
def sampler : Picture :=
  let label (x y : Float) (s : String) : Picture := .text x y 13 0x7aa2f7 s
  let box (y : Float) (a : Align) (s : String) : Picture :=
    .group [.rect 40 y 260 40 6 0x414868, .rect 42 (y + 2) 256 36 5 0x1a1b26,
            .textIn 54 y 236 40 16 a 0xc0caf5 s]
  .group [
    .rect 0 0 screenW screenH 0 0x24283b,
    label 40 40 "line, 1 to 6 wide",
    .group ((List.range 6).map fun i =>
      let x := 40 + 36 * i.toFloat
      .line x 60 (x + 24) 160 (i.toFloat + 1) 0x7aa2f7),
    label 300 40 "circle and ring",
    .circle 360 110 50 0x9ece6a,
    .ring 490 110 50 4 0xe0af68,
    label 40 220 "textIn: left, center, right",
    box 236 .left "left", box 284 .center "center", box 332 .right "right",
    label 360 220 "lines at angles",
    .ring 440 320 70 2 0x565f89,
    .group ((List.range 12).map fun i =>
      let a := i.toFloat * pi / 6
      .line (440 + 52 * a.sin) (320 - 52 * a.cos)
            (440 + 66 * a.sin) (320 - 66 * a.cos) 3 0xc0caf5),
    label 620 40 "translate, then clip to the gray box",
    .translate 620 60 (.group [
      .rect 0 0 200 120 0 0x414868,
      .clip 0 0 200 120 (.group [
        .circle 200 120 70 0xf7768e,
        .textIn 0 0 200 120 40 .center 0xc0caf5 "clipped text"])]),
    -- Drawn after the translate and clip: where it is says both were undone.
    label 620 220 "after them, back where it was",
    .circle 640 250 12 0xbb9af7 ]

-- The pure world, driven by a script of events instead of a person.
def test (c : Canvas) : IO Unit := do
  let grab := Event.press 300 (160 + 10)          -- Clock's title
  -- A press on the middle of item `i` of a menu at (x, y).
  let item (x y : Float) (i : Nat) : Event :=
    .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
  -- The menu opens Notes at (100, 400). Its body starts at (103, 428), so
  -- this press drops a dot at (40, 60) in its own coordinates.
  let dot := Event.press (103 + 40) (428 + 60)
  let script := [.tick ⟨10, 8, 30⟩,                 -- every app hears it
                 grab, .motion 1000 120, .release 1000 120,
                 .menu 600 450, item 600 450 0,     -- right-click, Clock
                 .motion 100 400, .key keyN,        -- N: the menu here
                 item 100 400 3,                    -- Notes
                 dot,
                 .press (80 + 420 - 15) (70 + 14),  -- REPL's close box
                 .tick ⟨10, 8, 31⟩]
  let d := script.foldl Desktop.step start
  IO.println s!"after the script: {d.now.windows.map (·.title)}, \
    focus {d.now.focus}, {d.past.length} earlier worlds"
  let clockWin := d.now.windows.find? (·.title == "Clock")
  IO.println s!"Clock at {clockWin.map (·.x)} {clockWin.map (·.y)}; \
    in the start world still at {(start.now.windows.find? (·.title == "Clock")).map (·.x)}"
  render c d.view; c.savePng "after-script.png"
  -- The menu open, the pointer on its second item.
  let open_ := (d.step (.menu 700 250)).step
    (.motion 720 (Menu.itemY ⟨700, 250⟩ 1 + 5))
  render c open_.view; c.savePng "menu.png"
  let off := open_.step (.press 20 20)
  IO.println s!"a press off the menu: menu open {off.now.menu.isSome}, \
    {off.now.windows.length} windows, {off.past.length} earlier worlds"
  let d := (d.step (.key keyU)).step (.key keyU)
  IO.println s!"after two undos: {d.now.windows.map (·.title)}"
  render c d.view; c.savePng "after-undo.png"
  render c sampler; c.savePng "sampler.png"

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
