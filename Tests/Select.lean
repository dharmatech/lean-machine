import Tests.Kit

/-! # `--test`: selecting in the editor

An editor alone on a scratch file: Shift and the moves select, either
way, a move without Shift ends the selection, and Ctrl+A selects it
all; what's typed, entered or pasted replaces the selection, and
Backspace and Delete take it out. A press and a drag select, and on
the desktop, a drag down Clock.lean and past the bottom of the view
(docs/design/editor/selecting.md). -/

namespace LeanMachine.Tests

-- What the editor has selected, and where its cursor is.
def showSelected (e : Editor) : String :=
  s!"{e.selected.quote}, cursor at {e.buffer.row + 1}:{e.buffer.col + 1}"

-- The point in an editor's body at line `row` and column `col` of
-- what's in view.
def atCell (row col : Nat) : Float × Float :=
  (Editor.textX + monoAdvance edFont * col.toFloat, Editor.rowY row + 5)

def testSelect (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "selecting in the editor:"
  let key (k : Key) : AppEvent := .key k {}
  let shift (k : Key) : AppEvent := .key k { shift := true }
  let ctrl (ch : Char) : AppEvent := .key (.char ch) { ctrl := true }
  let ed := editorNow svc
  let dir := testOut / "select"
  IO.FS.createDirAll dir
  IO.FS.writeFile (dir / "Scratch.lean") "def a := 1\ndef b := 2\ndef c := 3\n"
  let e ← ed {} [.tick ⟨10, 8, 30⟩]
  let e ← ed { e with files := #[".lake/test/select/Scratch.lean"] } [key .enter]
  let shows (what : String) (e : Editor) : IO Unit := IO.println s!"  {what}: {showSelected e}"
  -- Shift and the moves.
  let e ← ed e [shift .right, shift .right, shift .right]
  shows "Shift+Right three times" e
  let e ← ed e [shift .down]
  shows "and Shift+Down" e
  shows "and Shift+End" (← ed e [shift .«end»])
  shows "and Right, without Shift" (← ed e [key .right])
  let e ← ed e [key .down, key .«end», shift .up, shift .left, shift .left]
  shows "back from the end of line 3: Shift+Up, Shift+Left twice" e
  -- Typing, Enter, a paste, Backspace and Delete.
  let e1 ← ed e [.text "x"]
  IO.println s!"    \"x\" typed over it: {e1.buffer.text.quote}, {showSelected e1}"
  let e1 ← ed e [key .enter]
  IO.println s!"    Enter over it: {e1.buffer.text.quote}"
  let e1 ← ed e [.paste "one\ntwo"]
  IO.println s!"    \"one\\ntwo\" pasted over it: {e1.buffer.text.quote}, {showSelected e1}"
  let e1 ← ed e [key .backspace]
  IO.println s!"    Backspace: {e1.buffer.text.quote}, {e1.title}; Backspace again: \
    {(← ed e1 [key .backspace]).buffer.text.quote}"
  let e1 ← ed e [ctrl 'a']
  IO.println s!"  Ctrl+A: {showSelected e1}; Delete: {(← ed e1 [key .delete]).buffer.text.quote}"
  -- A press and a drag, in the body's own coordinates.
  let (x0, y0) := atCell 0 4
  let (x1, y1) := atCell 1 5
  let e ← ed e [key .home, .press x0 y0, .motion ((x0 + x1) / 2) ((y0 + y1) / 2), .motion x1 y1,
    .release x1 y1]
  shows "a drag from 1:5 to 2:6" e
  IO.println s!"    the pointer moved after the release: \
    {showSelected (← ed e [.motion x0 y0])}; a press: {showSelected (← ed e [.press x0 y0])}"
  -- On the desktop: Clock.lean, a drag from line 12 down into line 18,
  -- the status line, and a drag past the bottom of the view, which
  -- scrolls a line for each motion.
  let d ← [Event.menu 300 100, menuItem 300 100 2, .text "apps/cl", .key .enter {}].foldlM
    (stepNow svc) start
  let some w := winTitled d "Clock.lean" | throw (IO.userError "no Clock.lean")
  let (ax, ay) := atCell 11 0
  let (zx, zy) := atCell 17 20
  let d := steps d (dragBy (w.bodyX + ax) (w.bodyY + ay) (zx - ax) (zy - ay))
  IO.println s!"  on the desktop, a drag down Clock.lean: \
    {(says d "Clock.lean" "LeanMachine/Apps/Clock.lean").quote}"
  render c d.view; shot c "select-editor.png"
  let below := w.bodyY + w.bodyH + 30
  let d := steps d ([.press (w.bodyX + ax) (w.bodyY + ay)] ++
    (List.range 5).map (fun i => Event.motion (w.bodyX + 200) (below + i.toFloat)) ++
    [.release (w.bodyX + 200) below])
  IO.println s!"    a drag from line 12 to under the window, five motions there: \
    {(says d "Clock.lean" "LeanMachine/Apps/Clock.lean").quote}, \
    first line shown {(lineNumbers d "Clock.lean").head?.map (·.trimAscii.toString)}"

end LeanMachine.Tests
