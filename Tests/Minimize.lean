import Tests.Kit

/-! # `--test`: minimizing and the taskbar

Windows minimized and brought back, the taskbar's buttons, and the
boxes on a title (docs/design/world/minimizing.md,
docs/design/world/title-boxes.md). -/

namespace LeanMachine.Tests

-- Minimizing and the taskbar: the bar at the start; Notes minimized by
-- its box and brought back by its button, minimized by its button, and
-- undone; Ctrl+Shift+H until nothing is focused, then once more; a
-- maximized clock minimized, ticked, reloaded and brought back
-- maximized; a click on a button below a maximized window's edge, and on
-- the bar over a window under it; the hint giving way to more windows;
-- the boxes on a title showing what they do, with the pointer on them.
def testMinimize (c : Canvas) : IO Unit := do
  let start := steps start [.tick ⟨10, 8, 30⟩]
  let click (x y : Float) : List Event := [.press x y, .release x y]
  -- The middle of the button of the window titled `title`.
  let buttonX (d : Desktop) (title : String) : Float :=
    let bar := d.now.taskbar
    ((bar.buttons.find? (·.1.title == title)).map fun (_, x) => x + bar.w / 2).getD 0
  let button (d : Desktop) (title : String) : List Event :=
    click (buttonX d title) (barY + barH / 2)
  let focused (d : Desktop) : String :=
    ((d.now.windows.find? (·.id == d.now.focus)).map (·.title)).getD "nothing"
  let front (d : Desktop) : String := ((d.now.visible.getLast?.map (·.title))).getD "nothing"
  let state (d : Desktop) (title : String) : String :=
    match winTitled d title with
    | some w => s!"{showRect w.rect}{if w.maximized then ", maximized" else ""}\
        {if w.minimized then ", minimized" else ""}"
    | none => "no such window"
  let bar (d : Desktop) : String :=
    let b := d.now.taskbar
    s!"{d.now.windows.length} windows, buttons {showNum b.w} wide, the hint \
      {if b.hint then "shown" else "gone"}"
  let hkey : Event := .key (.char 'h') ctrlShift
  let mkey : Event := .key (.char 'm') ctrlShift
  IO.println s!"the taskbar: {bar start}, at \
    {start.now.taskbar.buttons.map fun (w, x) => s!"{w.title} {showNum x}"}; focus on {focused start}"
  -- Notes (500, 340) 420 × 260: its minimize box is at (862, 354).
  let d := steps start (click 862 354)
  IO.println s!"minimizing; Notes' box: {state d "Notes"}; focus on {focused d}; \
    {d.past.length} earlier worlds; a press where it was finds \
    {((d.now.grabAt 880 580).map (·.1.title)).getD "nothing"}"
  render c (d.step (.motion (buttonX d "Clock") (barY + 10))).view; shot c "taskbar.png"
  let d := steps d (button d "Notes")
  IO.println s!"  its button: {state d "Notes"}; in front {front d}; focus on {focused d}; \
    {d.past.length} earlier worlds"
  let d := steps d (button d "Notes")
  IO.println s!"  its button again: {state d "Notes"}; focus on {focused d}"
  let u := d.step undoKey
  IO.println s!"  undo: {state u "Notes"}; focus on {focused u}"
  let d := steps d [hkey]
  IO.println s!"  Ctrl+Shift+H: Inspector {state d "Inspector"}; focus on {focused d}"
  let d := steps d [hkey, hkey]
  IO.println s!"  twice more: focus on {focused d}; {d.now.visible.length} windows showing; \
    {d.past.length} earlier worlds"
  let d := steps d [hkey]
  IO.println s!"  once more, nothing focused: {d.past.length} earlier worlds"
  let d := steps d (button d "Inspector")
  IO.println s!"  Inspector's button: {state d "Inspector"}; focus on {focused d}"
  -- Clock (220, 160): maximized, minimized and ticked while minimized.
  let d := steps start (click 300 170 ++ [mkey, hkey, .tick ⟨10, 9, 0⟩])
  IO.println s!"Clock maximized, Ctrl+Shift+H, a tick at 10:09:00: {state d "Clock"}; \
    focus on {focused d}"
  let d := steps d (button d "Clock")
  IO.println s!"  its button: {state d "Clock"}; it says {(says d "Clock" "10:").quote}"
  let d := (steps d (button d "Clock")).step (.reload 0 [(``clock, clock)])
  IO.println s!"  its button again, then reloaded: {state d "Clock"}"
  let d := steps d (button d "Clock")
  IO.println s!"  its button: {state d "Clock"}"
  let d := steps d (click (screenW - 35) 14)
  IO.println s!"  its green box: {state d "Clock"}"
  -- Inspector maximized: its bottom edge, which can be grabbed from 4
  -- below it, is at the top of the bar. The pointer 2 below it, on
  -- Clock's button.
  let d := steps start (click 500 260 ++ [mkey])
  let d := steps d [.motion (buttonX d "Clock") (barY + 2)]
  IO.println s!"Inspector maximized, the pointer 2 into the bar on Clock's button: lit \
    {(d.now.lit.map fun (id, es) => s!"window {id}, {es.show}").getD "nothing"}"
  let d := steps d (click (buttonX d "Clock") (barY + 2))
  IO.println s!"  a click there: focus on {focused d}, in front {front d}; Inspector {state d "Inspector"}"
  -- Notes dragged 300 down, under the bar, then Clock's title clicked.
  let d := steps start (dragBy 600 350 0 300 ++ click 300 170)
  let before := d.past.length
  let d := steps d (click 900 790)
  IO.println s!"Notes under the bar, {state d "Notes"}; a click on the bar over it, off the \
    buttons: focus on {focused d}, in front {front d}, {d.past.length - before} more earlier worlds"
  let d := steps d (dragBy 600 650 0 300)
  IO.println s!"  Notes dragged 300 further down: {state d "Notes"}, its title's top \
    {showNum titleKept} above the bar"
  -- More windows, from the menu: Clock, Inspector, Notes, Clock.
  let item (x y : Float) (i : Nat) : Event := .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
  let mut more := start
  for (i, k) in [(0 : Nat), 3, 4, 0].zipIdx do
    let x := 640 + 30 * k.toFloat
    let y := 60 + 30 * k.toFloat
    more := steps more [.menu x y, item x y i]
    IO.println s!"  {bar more}"
  let d := more
  let d := steps d (button d "REPL" ++ button d "REPL" ++ button d "Inspector" ++ button d "Inspector")
  let d := d.step (.motion (buttonX d "Notes") (barY + 10))
  IO.println s!"  REPL and the first Inspector minimized: focus on {focused d}"
  render c d.view; shot c "taskbar-many.png"
  -- The pointer on the boxes of a title, which show what they do. The
  -- REPL (80, 70) 566 × 331, behind: its boxes from x = 580 to its right
  -- edge at 646, its title from y = 70 to 98.
  let boxesAt (d : Desktop) (x y : Float) : String :=
    let d := d.step (.motion x y)
    ((d.now.boxesLit.bind fun id => d.now.windows.find? (·.id == id)).map (·.title)).getD "none"
  IO.println s!"the boxes lit with the pointer on the REPL's minimize box: \
    {boxesAt start 590 84}; on its title left of them: {boxesAt start 570 84}; on its top \
    edge above them: {boxesAt start 630 71}; on its right edge: {boxesAt start 644 84}"
  render c (start.step (.motion 610 84)).view; shot c "boxes.png"
  let d := steps start (click 885 354)
  IO.println s!"  Notes maximized, the pointer on its green box: {boxesAt d (screenW - 36) 14}"
  render c (d.step (.motion (screenW - 36) 14)).view; shot c "boxes-max.png"

end LeanMachine.Tests
