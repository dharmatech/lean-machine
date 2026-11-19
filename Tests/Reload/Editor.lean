import Tests.Reload.Kit

/-! # `--test`: reloading from an editor alone

Clock.lean reloaded by an editor with no desktop around it, then with
an error, which the editor marks (docs/design/reloading/README.md). -/

namespace LeanMachine.Tests

-- An editor alone, its requests answered at once: Clock.lean reloaded
-- with Ctrl+R, then with a name Lean doesn't know, and again without it.
def reloadInEditor (svc : Services) : IO Unit := do
  let key (k : Key) : AppEvent := .key k {}
  let ctrl (ch : Char) : AppEvent := .key (.char ch) { ctrl := true }
  let ed := editorNow svc
  let fileOf (e : Editor) : List Lexed := e.buffer.above.reverse ++ e.buffer.current :: e.buffer.below
  let lineWith (e : Editor) (s : String) : String :=
    ((fileOf e).find? (·.text.startsWith s)).map showLexed |>.getD "?"
  let marked (e : Editor) : List String := (fileOf e).zipIdx.filterMap fun (l, i) =>
    if l.said.isEmpty then none else some s!"line {i + 1}: {l.said.map (·.2.show)}"
  let e ← ed {} [.tick ⟨10, 8, 30⟩, .text "apps/cl", key .enter]
  IO.println s!"an editor alone, on {e.title}: {lineWith e "    clockFace"}"
  let e ← ed e [ctrl 'r']
  IO.println s!"  Ctrl+R: {e.note.quote}, now {lineWith e "    clockFace"}"
  -- Line 14 is `  s!"{two t.hour}:…"`: a name Lean doesn't know, after `s!"`.
  let e ← ed e ([AppEvent.key .home { ctrl := true }] ++ List.replicate 13 (key .down) ++
    List.replicate 5 (key .right) ++ [.text "NEW {oops} ", ctrl 'r'])
  IO.println s!"  `NEW \{oops}` on line 14, Ctrl+R: {e.note.quote}, {e.title}; marked: {marked e}"
  let e ← ed e (List.replicate 7 (key .backspace) ++ [ctrl 'r'])
  IO.println s!"  `\{oops} ` deleted, Ctrl+R: {e.note.quote}; marked: {marked e}"

end LeanMachine.Tests
