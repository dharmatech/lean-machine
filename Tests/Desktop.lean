import Tests.Kit

/-! # `--test`: the desktop

The pure world driven by a script of events: windows dragged, the menu,
Notes typed into, undo; `sampler`, one of each kind of picture; what
the decoder makes of events; and the REPL typed into and edited, alone
and on the desktop. -/

namespace LeanMachine.Tests

-- One of each kind of picture, for `--test`: lines, circles, text placed in
-- boxes, and a picture moved and cut to a box.
def sampler : Picture :=
  let label (x y : Float) (s : String) : Picture := .text x y 13 0x7aa2f7 s
  let cells (x y size : Float) (n : Nat) : Picture :=
    .group ((List.range (n + 1)).map fun i =>
      let cx := x + monoAdvance size * i.toFloat
      .line cx y cx (y + 5) 1 0x565f89)
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
    .circle 640 250 12 0xbb9af7,
    -- Ticks at the cells' edges: each character, narrow or wide, in its own.
    label 40 440 "mono: a cell per character, a cursor after column 4",
    .mono 40 480 15 0xc0caf5 "let x := 42 -- héllo",
    cells 40 486 15 20,
    .rect (40 + monoAdvance 15 * 4) (480 - 13) 2 17 0 0xf7768e,
    .mono 40 540 24 0x9ece6a "iiiii MMMMM 01234",
    cells 40 548 24 17 ]

-- The pure world, driven by a script of events instead of a person.
def test (c : Canvas) (svc : Services) : IO Unit := do
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
                 .motion 100 400,
                 .key (.char 'n') ctrlShift,        -- the menu here
                 item 100 400 4,                    -- Notes
                 dot,
                 -- Notes hears typing. A plain or shifted N types; only
                 -- Ctrl+Shift+N is the desktop's.
                 .text "héllo, ", .text "wörld ",
                 .key (.char 'n') {}, .text "n",
                 .key (.char 'n') { shift := true }, .text "N",
                 .key .left { ctrl := true, shift := true },
                 .press (80 + repl.size.1 + 2 * frame - 15) (70 + 14), -- REPL's close box
                 .tick ⟨10, 8, 31⟩]
  let d := script.foldl Desktop.step start
  IO.println s!"after the script: {d.now.windows.map (·.title)}, \
    focus {d.now.focus}, {d.past.length} earlier worlds, \
    menu open {d.now.menu.isSome}"
  let clockWin := d.now.windows.find? (·.title == "Clock")
  IO.println s!"Clock at {clockWin.map (·.x)} {clockWin.map (·.y)}; \
    in the start world still at {(start.now.windows.find? (·.title == "Clock")).map (·.x)}"
  render c d.view; shot c "after-script.png"
  -- The menu open, the pointer on its second item.
  let open_ := (d.step (.menu 700 250)).step
    (.motion 720 (Menu.itemY ⟨700, 250⟩ 1 + 5))
  render c open_.view; shot c "menu.png"
  let off := open_.step (.press 20 20)
  IO.println s!"a press off the menu: menu open {off.now.menu.isSome}, \
    {off.now.windows.length} windows, {off.past.length} earlier worlds"
  let undo := Event.key (.char 'z') ctrlShift
  let d := (d.step undo).step undo
  IO.println s!"after two undos: {d.now.windows.map (·.title)}"
  render c d.view; shot c "after-undo.png"
  render c sampler; shot c "sampler.png"
  -- What the decoder makes of events as the shim hands them back.
  let raw (kind a b : Float) (text := "") : RawEvent := ⟨⟨#[kind, a, b, 0]⟩, text⟩
  let shown : Option Event → String
    | some (.key k m) => k.show m
    | some (.text s) => s!"text {s.quote}"
    | some _ => "another event"
    | none => "nothing"
  let decoded := [raw 5 78 0x41, raw 5 0x40000050 0, raw 5 13 0x200,
                  raw 6 0x40 0 "n", raw 6 0 0 "é"].map (shown ∘ Event.decode)
  IO.println s!"decoded: {decoded}"
  IO.println s!"mono: the font's advance is {← c.monoEm} em, the grid's \
    {monoAdvance 1} em"
  -- The REPL, typed into and edited: first a `Repl` alone, its lines
  -- evaluated at once, then on the desktop after a press in its body
  -- (left of Clock) focuses it.
  let key (k : Key) : AppEvent := .key k {}
  let line (s : String) : List AppEvent := [.text s, key .enter]
  let typing : List AppEvent :=
    line "1 + 1" ++
    [.text "\"helo\"", key .left, key .left, .text "l",  -- "hello"
     key .home, .text "String.length ", key .enter,
     .text "xabc", key .home, key .delete, key .enter,     -- abc: unknown
     key .backspace, key .enter] ++                        -- empty: asks nothing
    (List.range 10).flatMap (fun i => line s!"{i + 1} * {i + 1}") ++
    line (String.join (List.replicate 14 "1234567890")) ++ -- wraps
    [.text "draft", key .up, key .up, key .down, key .down, -- the draft again
     key .left, key .left]
  let r ← typing.foldlM (hearNow svc) ({} : Repl)
  let entry : Entry → String
    | .note s => s!"note {s.quote}"
    | .input s _ => s!"> {s}"
    | .output s => s
    | .warning s => s!"warning {s.quote}"
    | .error s => s!"error {s.quote}"
  IO.println s!"REPL line {(String.ofList (r.line.before.reverse ++ '|' :: r.line.after)).quote}, \
    {r.history.length} lines of history, \
    transcript starts {(r.transcript.reverse.take 7).map entry}"
  let r ← [key .up, key .up, key .up].foldlM (hearNow svc) r
  IO.println s!"three Ups: {r.line.text.quote}"
  let toEvent : AppEvent → Option Event
    | .text s => some (.text s)
    | .key k m => some (.key k m)
    | _ => none
  let d ← (Event.press 120 200 :: typing.filterMap toEvent).foldlM (stepNow svc) start
  IO.println s!"focused: {(d.now.windows.find? (·.id == d.now.focus)).map (·.title)}"
  render c d.view; shot c "repl.png"

end LeanMachine.Tests
