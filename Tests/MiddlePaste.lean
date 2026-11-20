import Tests.Select
import Tests.ReplCopy

/-! # `--test`: a middle click pastes the primary selection, and selecting sets it

What the decoder makes of the middle button. In an editor alone, a
middle click in the file with a line selected elsewhere; in a REPL
alone, a middle click on its line and on its transcript. On the
desktop, a middle click under the REPL's line with Notes focused, undo,
and a middle click on Notes' title. The primary selection is the loop's
(Main.lean), so the tests hand its text over as `Event.pasteAt`
(docs/design/drawing/middle-click-pastes.md). Then what each event
asks for as an editor alone and a REPL alone select, and a drag over
the desktop's REPL: a selection that settles asks to be the primary
selection (`Request.select`). -/

namespace LeanMachine.Tests

-- What `step` asks for at each of `evs` in turn, from `s`.
def askedAtEach {σ : Type} (step : σ → AppEvent → Option (σ × List Request)) (s : σ)
    (evs : List AppEvent) : List (List String) :=
  (evs.foldl (init := (s, [])) fun (s, out) ev =>
    match step s ev with
    | some (s', rs) => (s', out ++ [rs.map (·.show)])
    | none => (s, out ++ [[]])).2

def testMiddlePaste (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "a middle click pastes:"
  -- The decoder: buttons 1, 2 and 3 pressed, and 2 released.
  let raw (kind button : Float) : RawEvent := ⟨⟨#[kind, 10, 20, button]⟩, ""⟩
  let shown : Option Event → String
    | some (.press ..) => "press"
    | some (.middle x y) => s!"middle at {showNum x}, {showNum y}"
    | some (.menu ..) => "menu"
    | some _ => "another event"
    | none => "nothing"
  IO.println s!"  decoded, buttons 1, 2 and 3 down, then 2 up: \
    {[raw 2 1, raw 2 2, raw 2 3, raw 3 2].map (shown ∘ Event.decode)}"
  -- The editor alone: line 1 selected, a middle click after `:= ` on
  -- line 2.
  let ed := editorNow svc
  let dir := testOut / "middle"
  IO.FS.createDirAll dir
  IO.FS.writeFile (dir / "Scratch.lean") "def a := 1\ndef b := 2\ndef c := 3\n"
  let e ← ed {} [.tick ⟨10, 8, 30⟩]
  let opened ← ed { e with files := #[".lake/test/middle/Scratch.lean"] } [.key .enter {}]
  let e ← ed opened [.key .«end» { shift := true }]
  let (x, y) := atCell 1 9
  let e ← ed e [.pasteAt x y "x + "]
  IO.println s!"  in the editor, line 1 selected, a middle click at 2:10: {e.buffer.text.quote}, \
    {showSelected e}, {e.title}"
  -- The REPL alone: a middle click before the 2 of its line, then End and
  -- one on the transcript, which pastes at the cursor.
  let r ← [AppEvent.tick ⟨10, 8, 30⟩, .text "12 * 12", .key .enter {}, .text "1 + 2"].foldlM
    (hearNow svc) {}
  let (x, y) := replAt r "> 1 + 2" 6
  let r ← hearNow svc r (.pasteAt x y "3 * ")
  IO.println s!"  in the REPL, a middle click before the 2 of 1 + 2: {r.line.text.quote}, \
    cursor at {r.line.cursor}"
  let (x, y) := replAt r "144"
  let r ← [.key .«end» {}, .pasteAt x y " - 1"].foldlM (hearNow svc) r
  IO.println s!"    then End, and one on 144: {r.line.text.quote}"
  -- On the desktop: Notes focused, a middle click under the REPL's line
  -- (where nothing else is), and undo.
  let some n := winTitled start "Notes" | throw (IO.userError "no Notes")
  let d ← stepNow svc start (.press (n.bodyX + 50) (n.bodyY + 50))
  let some w := winTitled d "REPL" | throw (IO.userError "no REPL")
  let d ← stepNow svc d (.pasteAt (w.bodyX + 100) (w.bodyY + 250) "#eval 6 * 7")
  render c d.view; shot c "middle-paste.png"
  let undone := d.step undoKey
  IO.println s!"  on the desktop, Notes focused, a middle click under the REPL's line: \
    {focused d} focused, its line {(replLine d).quote}; after undo: {focused undone}, \
    {(replLine undone).quote}"
  -- Notes' title, right of the REPL, which is in front now.
  let title := Event.pasteAt (n.x + 200) (n.y + 10) "x"
  IO.println s!"  a middle click on Notes' title: {focused (d.step title)} focused, \
    a step undo returns to: {d.now.commits title}"
  IO.println s!"  the primary selection without a window: {(← Host.primarySelection).quote}"
  -- Selecting: Shift+Right three times, Right, a press, a motion and a
  -- release from 1:1 to 2:4, Ctrl+A, Ctrl+C and "x" typed over it all.
  let shift (k : Key) : AppEvent := .key k { shift := true }
  let ctrl (ch : Char) : AppEvent := .key (.char ch) { ctrl := true }
  let (x0, y0) := atCell 0 0
  let (x1, y1) := atCell 1 3
  IO.println s!"  selecting in the editor, what each event asks for: \
    {askedAtEach Editor.step opened [shift .right, shift .right, shift .right, .key .right {},
      .press x0 y0, .motion x1 y1, .release x1 y1, ctrl 'a', ctrl 'c', .text "x"]}"
  -- The REPL: a drag over 144, a click, the drag again and Ctrl+C.
  let (a, b) := replAt r "144"
  let (z, w) := replAt r "144" 3
  let dragged : List AppEvent := [.press a b, .motion z w, .release z w]
  IO.println s!"  in the REPL: {askedAtEach Repl.step r
    (dragged ++ [.press 300 b, .release 300 b] ++ dragged ++ [ctrl 'c'])}"
  -- On the desktop, a drag over what `12 * 12` came to in the REPL.
  let (d, _) ← typedInRepl svc start ["12 * 12"]
  let some w := winTitled d "REPL" | throw (IO.userError "no REPL")
  let some (x, y, _) := (w.app.view w.bodyW w.bodyH).monoSpots.find? (·.2.2 == "144")
    | throw (IO.userError "no 144")
  let (x, y) := (w.bodyX + x, w.bodyY + y - 4)
  let (_, asked) := (steps d (dragBy x y (monoAdvance replFont * 3) 0)).takeAsked
  IO.println s!"  on the desktop, a drag over 144 in the REPL: {asked.map (·.request.show)}"

end LeanMachine.Tests
