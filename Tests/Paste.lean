import Tests.Kit

/-! # `--test`: paste

What a paste key finds on the clipboard, as the editor and the REPL
take it: in the editor as lines, each read with what the line before
left open; in the REPL as its line, or a note for several lines; and
on the desktop, where undo takes a paste back alone. The clipboard is
the loop's (Main.lean), so the tests hand its text over as a paste
event (docs/design/drawing/paste-is-an-event.md). -/

namespace LeanMachine.Tests

-- The REPL's line on the desktop, as its window draws it: the runs from
-- the last prompt on.
def replLine (d : Desktop) : String :=
  let ts := ((winTitled d "REPL").map (·.texts)).getD []
  let back := (ts.reverse.findIdx? (·.startsWith "> ")).getD 0
  String.join (ts.drop (ts.length - 1 - back))

def testPaste (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "paste:"
  let key (k : Key) : AppEvent := .key k {}
  -- The editor alone on a scratch file: at the start of its second
  -- line, two lines with Windows line ends, a tab, and a comment that
  -- the first opens and the second closes, then a line end.
  let ed := editorNow svc
  let dir := testOut / "paste"
  IO.FS.createDirAll dir
  IO.FS.writeFile (dir / "Scratch.lean") "def a := 1\ndef b := 2\n"
  let e ← ed {} [.tick ⟨10, 8, 30⟩]
  let e ← ed { e with files := #[".lake/test/paste/Scratch.lean"] } [key .enter]
  let e ← ed e [key .down, .paste "def c := 3 /- a comment\r\n\tthat ends -/\r\n"]
  IO.println s!"  in the editor, at 2:1: {e.title}, cursor at {e.buffer.row + 1}:{e.buffer.col + 1}"
  showFile e
  let e ← ed e [key .up, key .«end», .paste "x y"]
  IO.println s!"  one line, at the end of line 3: {e.buffer.current.text.quote}, \
    cursor at {e.buffer.row + 1}:{e.buffer.col + 1}"
  let e ← ed {} [.tick ⟨10, 8, 30⟩, .paste "apps/cl\nmore"]
  IO.println s!"  in the list of files: {e.filter.text.quote} typed, {e.shown.toList} shown"
  -- The REPL alone: a line with blank lines around it goes in the line,
  -- and Enter evaluates it; two lines only leave a note.
  let r ← hearNow svc {} (.tick ⟨10, 8, 30⟩)
  let r ← [.paste "\n#eval 2 + 3\n", key .enter, .paste "def p := 1\ndef q := 2"].foldlM
    (hearNow svc) r
  let entry : Entry → String
    | .note s => s!"note {s.quote}"
    | .input s _ => s!"> {s}"
    | .output s => s
    | _ => "?"
  IO.println s!"  in the REPL: {(r.transcript.take 3).reverse.map entry}"
  -- On the desktop: the REPL focused by a press, "1 + " typed and "2"
  -- pasted; undo takes back the paste and not the typing.
  let d ← [Event.press 120 200, .text "1 + ", .paste "2"].foldlM (stepNow svc) start
  IO.println s!"  on the desktop, the REPL: {(replLine d).quote}; \
    after undo: {(replLine (d.step undoKey)).quote}"
  -- Clock.lean in an editor, and a snippet pasted at its line 10, under
  -- `namespace LeanMachine`.
  let d ← [Event.menu 300 100, menuItem 300 100 2, .text "apps/cl", .key .enter {}].foldlM
    (stepNow svc) d
  let d ← ((List.replicate 9 (Event.key .down {})) ++
    [Event.paste "-- Pasted from outside:\ndef twice (n : Nat) : Nat :=\n  2 * n\n\n"]).foldlM
    (stepNow svc) d
  IO.println s!"  the editor on the desktop: {focused d}, lines {(lineNumbers d (focused d)).length} in view; \
    after undo: {focused (d.step undoKey)}"
  render c d.view; shot c "paste-editor.png"
  -- What `sv_host_clipboard` gives without a window: nothing.
  IO.println s!"  the clipboard without a window: {(← Host.clipboard).quote}"

end LeanMachine.Tests
