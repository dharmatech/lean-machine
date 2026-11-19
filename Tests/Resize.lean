import Tests.Kit

/-! # `--test`: resizing windows

By an edge, a corner and the grip, an editor told its sizes, and a
reload that keeps a window's size (docs/design/world/resizing.md). -/

namespace LeanMachine.Tests

-- Resizing windows: by an edge, a corner and the grip, down to the
-- smallest size and up to the desktop's edges, with what the apps hear,
-- what's lit, and undo; an editor alone told sizes, its cursor kept in
-- view; an editor on the desktop made shorter, and undone; a reload that
-- keeps the size of the window it replaces the app in.
def testResize (c : Canvas) (svc : Services) : IO Unit := do
  let n := showNum
  let drag := dragBy
  let win := winTitled
  let undo := undoKey
  let d := steps start [.tick ⟨10, 8, 30⟩]
  IO.println s!"resizing; the windows at the start: \
    {d.now.windows.map fun w => s!"{w.title} {showRect w.rect}"}"
  IO.println s!"  Notes as it opens: {(says d "Notes" "size:").quote}"
  let d := steps d (drag 915 595 180 100)
  IO.println s!"  Notes by its grip, (+180, +100): {rectOf d "Notes"}, \
    {(says d "Notes" "size:").quote}; {d.past.length} earlier worlds"
  let d := steps d (drag 600 350 (-50) (-20))
  IO.println s!"  Notes moved by its title, (-50, -20): {rectOf d "Notes"}, \
    {(says d "Notes" "size:").quote}"
  let d := steps d (drag 361 300 500 0)
  IO.println s!"  Inspector's left edge, +500: {rectOf d "Inspector"} (no narrower than \
    {n minW}), {(says d "Inspector" "size:").quote}"
  let d := steps d (drag 300 67 0 (-100))
  IO.println s!"  the REPL's top edge, grabbed 3 above it, -100: {rectOf d "REPL"} (stops at \
    the top)"
  let d := steps d (drag 222 448 (-100) 400)
  IO.println s!"  Clock's bottom left corner, (-100, +400): {rectOf d "Clock"} (stops at the bar); \
    {d.past.length} earlier worlds"
  let d := steps d [.motion 1051 500]
  IO.println s!"  the pointer 1 right of Notes: lit \
    {(d.now.lit.map fun (id, es) => s!"window {id}, {es.show}").getD "nothing"}"
  render c d.view; shot c "resize.png"
  let u := d.step undo
  IO.println s!"  undo: Clock {rectOf u "Clock"}; again: REPL {rectOf (u.step undo) "REPL"}"
  -- The editor alone, told its size.
  let key (k : Key) : AppEvent := .key k {}
  let ed (e : Editor) (evs : List AppEvent) : IO Editor := evs.foldlM (answerNow svc Editor.heard) e
  let e ← ed {} ([.tick ⟨10, 8, 30⟩, .resize 760 520, .text "apps/ed", key .enter] ++
    List.replicate 39 (key .down))
  IO.println s!"an editor alone on {e.title}, 760 × 520: {e.rows} rows, {e.cols} columns; \
    cursor on line {e.buffer.row + 1}, top line {e.top + 1}"
  let e ← ed e [.resize 760 200]
  IO.println s!"  told 760 × 200: {e.rows} rows; top line {e.top + 1}, so the cursor's is the last in view"
  let e ← ed e [.press (Editor.textX + 2) (edPad + edLineH * 2 + 5)]
  IO.println s!"  a press on the third row: cursor on line {e.buffer.row + 1}"
  let e ← ed e [.resize 300 520, key .«end»]
  IO.println s!"  told 300 × 520, End: {e.cols} columns; cursor at column {e.buffer.col + 1}, \
    first column in view {e.left + 1}"
  let e ← ed e [.resize (minW - 2 * frame) (minH - titleH - frame)]
  IO.println s!"  told the smallest size, {n (minW - 2 * frame)} × {n (minH - titleH - frame)}: \
    {e.rows} rows, {e.cols} columns; top line {e.top + 1}, first column {e.left + 1}"
  -- The editor on the desktop, on Clock.lean, its cursor on line 31, made
  -- 300 shorter by its bottom edge.
  let item (x y : Float) (i : Nat) : Event := .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
  let dkey (k : Key) : Event := .key k {}
  let d ← ([Event.menu 300 100, item 300 100 2, .text "apps/cl", dkey .enter] ++
    List.replicate 30 (dkey .down)).foldlM (stepNow svc) start
  -- The line numbers in view, first and last.
  let numbers (d : Desktop) : String :=
    let ns := (((win d "Clock.lean").map (·.texts)).getD []).filter fun s =>
      s.length == gutterCols - 1 && !s.trimAscii.isEmpty && s.trimAscii.toString.all Char.isDigit
    s!"lines {(ns.head?.map (·.trimAscii.toString)).getD "?"} to \
      {(ns.getLast?.map (·.trimAscii.toString)).getD "?"} in view"
  IO.println s!"an editor on the desktop, on Clock.lean: {rectOf d "Clock.lean"}, {numbers d}"
  let d ← (drag 600 649 0 (-300)).foldlM (stepNow svc) d
  IO.println s!"  its bottom edge 300 up: {rectOf d "Clock.lean"}, {numbers d}; \
    {(says d "Clock.lean" "LeanMachine/").quote}"
  render c d.view; shot c "resize-editor.png"
  let d := d.step undo
  IO.println s!"  undo: {rectOf d "Clock.lean"}, {numbers d}"
  -- A reload keeps the size of the window it puts the new app in.
  let d ← (drag 221 300 (-120) 0 ++ [Event.press 700 110, .release 700 110,
    .key (.char 'r') { ctrl := true }]).foldlM (stepNow svc) d
  IO.println s!"  Clock's left edge -120, then Ctrl+R in the editor: Clock {rectOf d "Clock"}; \
    {(says d "Clock.lean" "LeanMachine/").quote}"

end LeanMachine.Tests
