import Tests.Kit

/-! # `--test`: the editor

A file's lines read with what the line before left open, an editor
alone on a scratch file, then on the desktop with Clock.lean, and
what it costs (docs/design/editor/README.md). -/

namespace LeanMachine.Tests

-- The editor: lines read with what the line before left open, an editor
-- alone on a scratch file (opening, comments across lines, Enter, joins,
-- saving, leaving), then on the desktop with Clock.lean, and costs.
def testEditor (c : Canvas) (svc : Services) : IO Unit := do
  let r ← hearNow svc {} (.tick ⟨10, 8, 30⟩)
  let some env := r.env | throw (IO.userError "the REPL didn't get its Lean")
  IO.println "tokens of a file's lines, each starting where the one before left off:"
  let file := ["def x := 1 /- a comment", "  that /- nests -/ and", "  ends -/ def y := \"a string",
               "that ends\" ++ \"here\"", "/-- A doc comment", "-/ theorem t : True := trivial"]
  let _ ← file.foldlM (init := Carry.code) fun c l => do
    let (ts, c') := env.tokensFrom c l
    IO.println s!"  [{c.show}] {showTokens l ts} [→ {c'.show}]"
    return c'
  -- The editor alone, its requests answered at once.
  let key (k : Key) : AppEvent := .key k {}
  let ctrl (ch : Char) : AppEvent := .key (.char ch) { ctrl := true }
  let ed := editorNow svc
  let dir := testOut / "editor"
  IO.FS.createDirAll dir
  IO.FS.writeFile (dir / "Scratch.lean") "def a := 1\ndef b := 2\ndef c := 3\n"
  let path := ".lake/test/editor/Scratch.lean"
  let e ← ed {} [.tick ⟨10, 8, 30⟩]
  IO.println s!"the editor asks for its Lean ({e.env.isSome}) and the files: \
    {e.files.size} Lean files, {e.files.toList.take 4}…"
  -- Scratch.lean is in a hidden folder, so it isn't listed: the test lists it.
  let e ← ed { e with files := #[path] } [key .enter]
  IO.println s!"opened {e.title}: {e.buffer.count} lines, {e.note.quote}"
  let e ← ed e [.text "/- "]
  IO.println s!"  \"/- \" typed at the start: {e.title}"
  showFile e
  let e ← ed e [key .down, key .down, key .«end», .text " -/"]
  IO.println "  \" -/\" at the end of the third line:"
  showFile e
  let e ← ed e [key .down, .text "def d :=", key .enter, .text "4", key .enter, key .backspace,
    key .backspace, key .backspace, .text " -- the end"]
  IO.println s!"  Enter after `:=`, then Enter and Backspaces: cursor at {e.buffer.row + 1}:{e.buffer.col + 1}"
  showFile e
  let e ← ed e [ctrl 's']
  let disk ← IO.FS.readFile (dir / "Scratch.lean")
  IO.println s!"  Ctrl+S: {e.title}, {e.note.quote}; on disk: {disk.quote}; \
    left beside it: {← (dir / "Scratch.lean.saving").pathExists}"
  let e ← ed e [key .home, key .backspace, ctrl 'o']
  IO.println s!"  a change, then Ctrl+O: {e.title}, {e.note.quote}"
  let e ← ed e [ctrl 'o']
  IO.println s!"  Ctrl+O again: {e.title}, path {e.path}, {e.files.size} files listed again"
  -- On the desktop: Editor from the menu, then Clock.lean, found by typing.
  let d ← [Event.menu 300 100, menuItem 300 100 2].foldlM (stepNow svc) start
  let title (d : Desktop) := (d.now.windows.find? (·.id == d.now.focus)).map (·.title)
  IO.println s!"from the menu: {title d}"
  render c d.view; shot c "editor-files.png"
  let dkey (k : Key) : Event := .key k {}
  let d ← [Event.text "apps/cl", dkey .enter].foldlM (stepNow svc) d
  IO.println s!"\"apps/cl\", Enter: {title d}"
  -- Line 16 is `def clockFace …`; a new line in it, and Tab.
  let d ← ((List.replicate 16 (dkey .down)) ++ [dkey .«end», dkey .enter, .text "toward.",
    dkey .backspace, .text " + TimeOfDay.", dkey .tab]).foldlM (stepNow svc) d
  IO.println s!"Tab after `TimeOfDay.`: {title d}"
  render c d.view; shot c "editor-complete.png"
  -- A comment opened at the top runs to the end of the file; the wheel
  -- scrolls down to show it.
  let d ← [Event.key .home { ctrl := true }, .text "/- ", .wheel 600 300 (-3)].foldlM (stepNow svc) d
  render c d.view; shot c "editor-comment.png"
  -- The editor alone again: a press places the cursor, the wheel scrolls.
  let e ← ed e [.text "apps/ed", key .enter]
  let e ← ed e [.press (Editor.textX + monoAdvance edFont * 6 + 2) (edPad + 5)]
  IO.println s!"{e.title}: a press by the left edge of row 1, column 7: cursor at \
    {e.buffer.row + 1}:{e.buffer.col + 1}"
  let e ← ed e [.wheel 100 100 (-2), .wheel 100 100 (-0.2), .wheel 100 100 (-0.2)]
  IO.println s!"  the wheel down 2 steps, then two fifths: top line {e.top + 1}, cursor still at {e.buffer.row + 1}"
  -- Costs, on Repl.lean.
  IO.println "costs:"
  let text ← IO.FS.readFile (projectRoot / "LeanMachine/Apps/Repl.lean")
  let b := Buffer.ofText text
  let lexAllUs ← usPer 20 fun i => do
    if (Buffer.lexAll env (if i == 1000 then {} else b)).count == 0 then IO.println "?"
  let opened := Editor.opened { base := some env, env := some env } "Repl.lean" text 0
  let middle := { opened with buffer := opened.buffer.goTo 120 4 }.follow
  let keyUs ← usPer 2000 fun i => do
    if let some (e', _) := middle.heard (.text (Char.ofNat (97 + i % 26)).toString) then
      if e'.buffer.here.tokens.isEmpty then IO.println "?"
  let atTop := { opened with buffer := opened.buffer.goTo 0 0 }
  let commentUs ← usPer 20 fun i => do
    if let some (e', _) := atTop.heard (.text (if i == 1000 then "x" else "/-")) then
      if e'.buffer.below.getLast?.map (·.carry) == some .code then IO.println "?"
  let commented := { atTop with buffer := Buffer.relex env { atTop.buffer with
    line := atTop.buffer.line.insert "/-" |>.toStart } }
  let uncommentUs ← usPer 20 fun i => do
    if let some (e', _) := commented.heard (.key (if i == 1000 then .left else .delete) {}) then
      if e'.buffer.below.getLast?.map (·.carry) != some .code then IO.println "?"
  let downUs ← usPer 2000 fun i => do
    if let some (e', _) := middle.heard (.key (if i == 100000 then .up else .down) {}) then
      if e'.buffer.row == 0 then IO.println "?"
  IO.println s!"  Repl.lean, {b.count} lines: read every line {lexAllUs} µs; a keystroke on \
    line 121 (step and tokens) {keyUs} µs; \"/-\" typed at the top, every line below read \
    again {commentUs} µs; that \"/\" deleted, every line read again {uncommentUs} µs; \
    Down {downUs} µs"
  let pic := middle.view editorSize.1 editorSize.2
  let viewUs ← usPer 200 fun i => do
    if (middle.view (editorSize.1 + (i % 2).toFloat) editorSize.2).monos == 0 then IO.println "?"
  let drawUs ← usPer 200 fun i => do
    render c (middle.view (editorSize.1 + (i % 2).toFloat) editorSize.2)
  let frameUs ← usPer 50 fun _ => render c d.view
  IO.println s!"  an editor full of code: {pic.monos} monos; the view in {viewUs} µs, drawn in \
    {drawUs} µs; the desktop with it drawn in {frameUs} µs"

end LeanMachine.Tests
