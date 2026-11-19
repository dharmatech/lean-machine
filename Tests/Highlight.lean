import Tests.Kit

/-! # `--test`: highlighting and completion

The tokens the REPL's Lean reads in a line, what Tab makes of names,
on a REPL alone and on the desktop, and what each costs
(docs/design/highlighting/README.md). -/

namespace LeanMachine.Tests

-- Highlighting and completion: the tokens the REPL's Lean reads in a
-- line, what Tab makes of names with one completion and with several,
-- and what each costs.
def testLean (c : Canvas) (svc : Services) : IO Unit := do
  let entered := ["def sq (n : Nat) : Nat := n * n  -- squares",
                  "def squares := [1, 2, 3].map sq",
                  "#eval (sq 12, 'x', 2.5, \"twelve\", `Nat.succ, squares)",
                  "IO.println \"unterminated"]
  let editing := "List.map sq [1, 2, 3] |>.foldl (· + ·) 0 /- sum -/ ¿"
  -- A REPL alone: its Lean comes when it first hears a tick.
  let r ← hearNow svc {} (.tick ⟨10, 8, 30⟩)
  let some env := r.env | throw (IO.userError "the REPL didn't get its Lean")
  IO.println "tokens, as the REPL's Lean reads them:"
  for l in entered.take 1 ++ [editing] do
    IO.println s!"  {showTokens l (env.tokens l)}"
  let ctrlC : AppEvent := .key (.char 'c') { ctrl := true }
  let r ← (entered.flatMap fun l => [.text l, .key .enter {}]).foldlM (hearNow svc) r
  IO.println s!"  after the def: {showTokens "sq squares" ((r.env.getD env).tokens "sq squares")}"
  -- Tab after a name typed on a cleared line.
  IO.println "Tab completes:"
  for word in ["Busy.al", "monoAdv", "sq", "Picture.", "List.ma", "names", "zzq", "\"Nat.su"] do
    let r ← [ctrlC, .text word, .key .tab {}].foldlM (hearNow svc) r
    let offered := match r.offer with
      | some o => s!"{o.names.length} offered{if o.names.isEmpty then "" else s!": {o.names.take 12}"}"
      | none => "nothing offered"
    IO.println s!"  {word.quote} → {r.line.text.quote}, {offered}"
  -- On the desktop: the same lines, the line being edited, then Tab.
  let key (k : Key) : Event := .key k {}
  let d ← ([Event.press 120 200] ++
    entered.flatMap (fun l => [Event.text l, key .enter]) ++ [Event.text editing]).foldlM (stepNow svc) start
  render c d.view; shot c "repl-highlight.png"
  let d ← [.key (.char 'c') { ctrl := true }, .text "Picture.", key .tab].foldlM (stepNow svc) d
  render c d.view; shot c "repl-complete.png"
  let d ← [.key (.char 'c') { ctrl := true }, .text "List.ma", key .tab].foldlM (stepNow svc) d
  render c d.view; shot c "repl-complete-many.png"
  -- What it costs. A keystroke: the REPL steps, and its Lean reads the
  -- line again.
  let env := r.env.getD env
  let h := env.state.held
  IO.println "costs:"
  let lexUs ← usPer 2000 fun i => do
    if (env.tokens (editing.push (Char.ofNat (97 + i % 26)))).isEmpty then IO.println "?"
  -- Four times the line, with no error to stop the tokenizer early.
  let longLine := " ".intercalate (List.replicate 4 (editing.dropEnd 2).toString)
  let lexLongUs ← usPer 1000 fun i => do
    if (env.tokens (longLine.push (Char.ofNat (97 + i % 26)))).isEmpty then IO.println "?"
  let typed := ({ r with line := .ofString editing } : Repl).relex
  let keyUs ← usPer 2000 fun i => do
    if let some (r', _) := typed.step (.text (Char.ofNat (97 + i % 26)).toString) then
      if r'.tokens.isEmpty then IO.println "?"
  let parseUs ← usPer 2000 fun i => do
    if let .ok stx := Lean.Parser.runParserCategory h.cmd.env `term
        (editing.dropEnd 1 |>.toString |>.push (Char.ofNat (97 + i % 26))) then
      if stx.getNumArgs == 1000 then IO.println "?"
  IO.println s!"  tokens of a line of {editing.length} characters: {lexUs} µs; of \
    {longLine.length}: {lexLongUs} µs; a keystroke in the REPL (step and tokens): \
    {keyUs} µs; Lean's parser on the line, for comparison: {parseUs} µs"
  for word in ["Busy.al", "s", "List.ma", "Nat."] do
    let n := (env.complete word).size
    let us ← usPer 200 fun i => do
      if (env.complete (if i == 1000 then "" else word)).size == 1000000 then IO.println "?"
    IO.println s!"  Tab on {word.quote}: {n} names, {us} µs"
  let t0 ← IO.monoNanosNow
  let index := nameIndex h.cmd.env
  let names := index.fold (fun n _ l => n + l.length) 0
  IO.println s!"  the name index: {names} names in {index.size} namespaces, made in \
    {((← IO.monoNanosNow) - t0) / 1000000} ms, of {h.cmd.env.constants.map₁.size} constants imported"
  -- A REPL full of highlighted lines, drawn, against the same lines in
  -- one colour each.
  let full : Repl := { typed with transcript :=
    (List.replicate 15 (Entry.input editing (env.tokens editing))) ++ r.transcript }
  let plain : Repl := { full with tokens := #[], transcript := full.transcript.map fun
    | .input s _ => .input s #[] | e => e }
  for (name, repl) in [("highlighted", full), ("one colour", plain)] do
    let pic := repl.view 554 269
    let viewUs ← usPer 200 fun i => do
      if (repl.view (554 + (i % 2).toFloat) 269).monos == 0 then IO.println "?"
    let us ← usPer 200 fun i => do
      render c (repl.view (554 + (i % 2).toFloat) 269)
    IO.println s!"  a REPL window {name}: {pic.monos} monos; the view in {viewUs} µs, \
      the view drawn in {us} µs"

end LeanMachine.Tests
