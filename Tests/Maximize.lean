import Tests.Kit

/-! # `--test`: maximizing windows

By the box on a title, a double click and Ctrl+Shift+M, each undone,
and a maximized window dragged (docs/design/world/maximizing.md). -/

namespace LeanMachine.Tests

-- Maximizing and restoring: by the box on a title, a double click on
-- it and Ctrl+Shift+M, each undone; a maximized window dragged by its
-- title (restored under the pointer, past a nudge) and by an edge; a
-- reload that keeps a window maximized; an editor maximized.
def testMaximize (c : Canvas) (svc : Services) : IO Unit := do
  let start := steps start [.tick ⟨10, 8, 30⟩]
  let state (d : Desktop) (title : String) : String :=
    match winTitled d title with
    | some w => s!"{showRect w.rect}{if w.maximized then ", maximized" else ""}"
    | none => "no such window"
  let mkey : Event := .key (.char 'm') ctrlShift
  let click (x y : Float) : List Event := [.press x y, .release x y]
  -- Notes (500, 340) 420 × 260: its maximize box is at (885, 354).
  let d := steps start (click 885 354)
  IO.println s!"maximizing; Notes' box: {state d "Notes"}, \
    {(says d "Notes" "size:").quote}; {d.past.length} earlier worlds"
  let d := steps d (click (screenW - 35) 14)
  IO.println s!"  its box again: {state d "Notes"}, {(says d "Notes" "size:").quote}"
  -- Clock (220, 160) 236 × 290; its title is in front at (300, 170).
  let d := steps start (click 300 170 ++ [.press 300 170 2, .release 300 170])
  IO.println s!"  a double click on Clock's title: {state d "Clock"}; \
    {d.past.length} earlier worlds"
  IO.println s!"  undo: {state (d.step undoKey) "Clock"}"
  let d := steps d (click 300 10 ++ [.press 300 10 2, .release 300 10])
  IO.println s!"  a double click on it again: {state d "Clock"}"
  -- The REPL's title at (150, 80), then Ctrl+Shift+M.
  let d := steps start (click 150 80 ++ [mkey])
  IO.println s!"  Ctrl+Shift+M on the REPL: {state d "REPL"}; {d.past.length} earlier worlds"
  IO.println s!"  undo: {state (d.step undoKey) "REPL"}"
  -- Inspector (360, 250) 420 × 260, maximized, then dragged by its title
  -- from the middle of the screen.
  let d := steps start (click 500 260 ++ [mkey, .press 640 14, .motion 642 15])
  IO.println s!"  Inspector maximized, its title pressed in the middle and nudged 2: \
    {state d "Inspector"}"
  let d := steps d [.motion 640 114, .release 640 114]
  IO.println s!"  then 100 down: {state d "Inspector"}, {(says d "Inspector" "size:").quote} \
    (the pointer as far along its title as before)"
  let d := steps d ([mkey] ++ dragBy (screenW - 2) 400 (-300) 0)
  IO.println s!"  maximized again, its right edge -300: {state d "Inspector"}"
  -- A reload keeps a window maximized, and its place to go back to.
  let d := steps start (click 300 170 ++ [mkey])
  let d := d.step (.reload 0 [(``clock, clock)])
  IO.println s!"  Clock maximized, then reloaded: {state d "Clock"}"
  let d := steps d (click (screenW - 35) 14)
  IO.println s!"  its box: {state d "Clock"}"
  -- An editor on Clock.lean, maximized.
  let item (x y : Float) (i : Nat) : Event := .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
  let d ← [Event.menu 300 100, item 300 100 2, .text "apps/cl", .key .enter {}, mkey].foldlM
    (stepNow svc) start
  let rows := (((winTitled d "Clock.lean").map (·.texts)).getD []).filter fun s =>
    s.length == gutterCols - 1 && !s.trimAscii.isEmpty && s.trimAscii.toString.all Char.isDigit
  IO.println s!"  an editor on Clock.lean, Ctrl+Shift+M: {state d "Clock.lean"}, \
    {rows.length} lines in view"
  render c d.view; shot c "maximize.png"

end LeanMachine.Tests
