import Tests.Kit

/-! # `--test`: the screen resized

The world told the host's window has a new size (`Event.screen`):
windows kept on it, a maximized one filling it, the menu and the
taskbar, and undo, which keeps the screen as it is
(docs/design/world/screen.md). -/

namespace LeanMachine.Tests

-- The start desktop on a smaller screen and a bigger one, with each
-- window's place; a maximized window, which fills the new desktop and
-- is restored on it; undo, which keeps the screen; a screen that grows
-- back, which moves nothing; a window hanging off the right edge; a
-- screen smaller than a window.
def testScreen : IO Unit := do
  let start := steps start [.tick ⟨10, 8, 30⟩]
  let places (d : Desktop) : String :=
    ", ".intercalate (d.now.windows.map fun w =>
      s!"{w.title} {showRect w.rect}{if w.maximized then " maximized" else ""}")
  let screen (d : Desktop) : String := s!"{showNum d.now.screen.w} × {showNum d.now.screen.h}"
  let bar (d : Desktop) : String :=
    let b := d.now.taskbar
    s!"buttons {showNum b.w} wide from y = {showNum b.y}, hint {if b.hint then "shown" else "gone"}"
  let small : Event := .screen 900 600
  IO.println s!"the screen resized; at the start, {screen start}: {places start}; {bar start}"
  -- The menu opened at the bottom right, then the screen made smaller.
  let d := steps start [.menu 1270 790, small]
  IO.println s!"  900 × 600, the menu open at the bottom right: {places d}; \
    menu at {(d.now.menu.map fun m => s!"({showNum m.x}, {showNum m.y})").getD "none"}; \
    {bar d}; {d.past.length} earlier worlds"
  let c ← Canvas.new 900 600
  render c d.view; shot c "screen-small.png"
  let d := start.step (.screen 1600 1000)
  IO.println s!"  1600 × 1000: {places d}; {bar d}"
  let c ← Canvas.new 1600 1000
  render c d.view; shot c "screen-large.png"
  -- Notes (500, 340) 420 × 260 maximized by its box at (885, 354).
  let d := steps start (click 885 354 ++ [small])
  IO.println s!"  Notes maximized, then 900 × 600: {rectOf d "Notes"}, \
    {(says d "Notes" "size:").quote}"
  let d := steps d (click (d.now.screen.w - 35) 14)
  IO.println s!"  its box: {rectOf d "Notes"}, {(says d "Notes" "size:").quote}"
  -- Clock maximized by Ctrl+Shift+M on its title, the screen made
  -- smaller, then undo.
  let d := steps start (click 300 170 ++ [maximizeKey])
  let earlier := d.past.length
  let d := steps d [small]
  IO.println s!"  Clock maximized, {earlier} earlier worlds; 900 × 600, {d.past.length}"
  let d := d.step undoKey
  IO.println s!"  undo: the screen {screen d}; {places d}"
  let d := steps d [.screen 1280 800]
  IO.println s!"  back to {screen d}: {places d}"
  -- Notes dragged 500 right by its title, 140 of it off the edge.
  let d := steps start (dragBy 600 350 500 0)
  let d := steps d [small]
  IO.println s!"  Notes dragged 500 right, then 900 × 600: {rectOf d "Notes"}"
  let d := steps start [.screen 400 300]
  IO.println s!"  400 × 300: {places d}"

end LeanMachine.Tests
