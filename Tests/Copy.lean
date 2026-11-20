import Tests.Select

/-! # `--test`: copying and cutting in the editor

What Ctrl+C, Ctrl+Shift+C and Ctrl+X ask for (`Request.copy`) in an
editor alone, with a selection and without one, and while a reload
goes on; a cut and the copy pasted elsewhere, which moves the lines;
and on the desktop, lines of Clock.lean copied through the loop. The
clipboard is the loop's: without a window, a copy goes nowhere
(docs/design/editor/copy-and-cut.md). -/

namespace LeanMachine.Tests

def testCopy (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "copying and cutting in the editor:"
  let key (k : Key) : AppEvent := .key k {}
  let shift (k : Key) : AppEvent := .key k { shift := true }
  let ctrl (ch : Char) : AppEvent := .key (.char ch) { ctrl := true }
  let ed := editorNow svc
  let dir := testOut / "copy"
  IO.FS.createDirAll dir
  IO.FS.writeFile (dir / "Scratch.lean") "def a := 1\ndef b := 2\ndef c := 3\n"
  let e ← ed {} [.tick ⟨10, 8, 30⟩]
  let e ← ed { e with files := #[".lake/test/copy/Scratch.lean"] } [key .enter]
  -- What a key asks for, and what the editor says then.
  let asks (e : Editor) (ev : AppEvent) : String :=
    match e.heard ev with
    | some (e', rs) => s!"{rs.map (·.show)}, {e'.note.quote}"
    | none => "nothing"
  -- From 1:5 to 2:6, by Shift and the moves.
  let sel ← ed e [key .right, key .right, key .right, key .right, shift .down, shift .right]
  IO.println s!"  {sel.selected.quote} selected: Ctrl+C {asks sel (ctrl 'c')}; \
    Ctrl+Shift+C {asks sel (.key (.char 'c') ctrlShift)}"
  let none_ ← ed sel [key .right]
  IO.println s!"  nothing selected: Ctrl+C {asks none_ (ctrl 'c')}; Ctrl+X {asks none_ (ctrl 'x')}; \
    while a reload goes on, Ctrl+C {asks { none_ with reloading := true } (ctrl 'c')}, \
    Ctrl+Shift+C {asks { none_ with reloading := true } (.key (.char 'c') ctrlShift)}"
  -- Ctrl+X, then what it copied pasted at the end of the file.
  let some (cut, rs) := sel.heard (ctrl 'x') | throw (IO.userError "Ctrl+X asked nothing")
  IO.println s!"  Ctrl+X: {rs.map (·.show)}, {cut.title}, {cut.note.quote}, \
    {cut.buffer.text.quote}, cursor at {cut.buffer.row + 1}:{cut.buffer.col + 1}"
  let copied := match rs with | [.copy s] => s | _ => ""
  let moved ← ed cut [.key .«end» { ctrl := true }, .paste copied]
  IO.println s!"    and pasted at the end: {moved.buffer.text.quote}"
  -- On the desktop: Clock.lean, lines 12 to 18 selected by a drag, and
  -- Ctrl+C, through the loop's `Runs.handle`.
  let d ← [Event.menu 300 100, menuItem 300 100 2, .text "apps/cl", .key .enter {}].foldlM
    (stepNow svc) start
  let some w := winTitled d "Clock.lean" | throw (IO.userError "no Clock.lean")
  let (ax, ay) := atCell 11 0
  let (zx, zy) := atCell 17 20
  let d := steps d (dragBy (w.bodyX + ax) (w.bodyY + ay) (zx - ax) (zy - ay))
  let d ← stepNow svc d (.key (.char 'c') { ctrl := true })
  IO.println s!"  on the desktop, lines 12 to 18 of Clock.lean, Ctrl+C: \
    {(says d "Clock.lean" "LeanMachine/Apps/Clock.lean").quote}, title {focused d}"
  render c d.view; shot c "copy-editor.png"

end LeanMachine.Tests
