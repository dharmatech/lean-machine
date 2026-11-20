import Tests.Paste

/-! # `--test`: selecting, copying and clicking in the REPL

A REPL alone, its lines evaluated at once: drags over an output, part
of a line entered, a block of two lines, a list that wraps, and past
one entry, where the prompts come along; a drag below the rows. What
Ctrl+C and Ctrl+Shift+C ask for with a selection and without, with a
run going and not, and a key that ends the selection. Clicks in the
line, which move its cursor, a drag in it, and clicks on what Tab
offered and below the rows. On the desktop, a drag over the REPL's
transcript and Ctrl+C, which asks the loop to copy, and a click in its
line (docs/design/lean/copying-from-the-repl.md). -/

namespace LeanMachine

-- Each `mono` a picture draws: where its text starts, and the text.
partial def Picture.monoSpots : Picture → List (Float × Float × String)
  | .mono x y _ _ s => [(x, y, s)]
  | .group ps => ps.flatMap (·.monoSpots)
  | .translate dx dy p => p.monoSpots.map fun (x, y, s) => (x + dx, y + dy, s)
  | .clip _ _ _ _ p => p.monoSpots
  | _ => []

end LeanMachine

namespace LeanMachine.Tests

-- A row of the REPL as it's drawn: its runs at their columns.
def rowText (row : Row) : String :=
  row.foldl (init := "") fun s run => s.pushn ' ' (run.col - s.length) ++ run.text

-- The point before character `k` of `s`, in the first row of the
-- REPL's view that shows `s`.
def replAt (r : Repl) (s : String) (k : Nat := 0) : Float × Float := Id.run do
  let l := r.layout r.size.1 r.size.2
  let want := s.toList
  for (v, i) in l.rows.zipIdx do
    let cs := (rowText v.row).toList
    if let some c := (List.range cs.length).find? (fun j => (cs.drop j).take want.length == want) then
      return (replPad + monoAdvance replFont * (c + k).toFloat, replPad + replLineH * i.toFloat + 10)
  return (0, 0)

def testReplCopy (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "selecting, copying and clicking in the REPL:"
  let key (k : Key) : AppEvent := .key k {}
  let ctrlC : AppEvent := .key (.char 'c') { ctrl := true }
  let ctrlShiftC : AppEvent := .key (.char 'c') ctrlShift
  -- A REPL alone: a definition, a line that uses it, a block of two
  -- lines, a list that wraps, and a line being typed.
  let r ← hearNow svc {} (.tick ⟨10, 8, 30⟩)
  let r ← [.text "def sq (n : Nat) := n * n", key .enter, .text "sq 12", key .enter,
    .paste "def twice (n : Nat) : Nat :=\n  2 * n", key .enter,
    .text "List.range 30", key .enter, .text "twice"].foldlM (hearNow svc) r
  -- A press at `a`, the pointer moved to `z`, and a release there.
  let drag (r : Repl) (a z : Float × Float) : IO Repl :=
    [.press a.1 a.2, .motion ((a.1 + z.1) / 2) ((a.2 + z.2) / 2), .motion z.1 z.2,
      .release z.1 z.2].foldlM (hearNow svc) r
  let shows (what : String) (r : Repl) : IO Unit := IO.println s!"  {what}: {r.selected.quote}"
  -- What a key asks for, and whether the selection is still there then.
  let asks (r : Repl) (ev : AppEvent) : String :=
    match r.heard ev with
    | some (r', rs) =>
      s!"{rs.map (·.show)}, {if r'.selection.isSome then "still selected" else "nothing selected"}"
    | none => "nothing"
  let out ← drag r (replAt r "144") (replAt r "144" 3)
  shows "a drag over 144" out
  IO.println s!"    Ctrl+C {asks out ctrlC}; Ctrl+Shift+C {asks out ctrlShiftC}"
  shows "part of a line entered" (← drag r (replAt r "> sq 12" 2) (replAt r "> sq 12" 7))
  shows "from its prompt to the end of 144" (← drag r (replAt r "> sq 12") (replAt r "144" 3))
  shows "the block, without its prompt"
    (← drag r (replAt r "> def twice" 2) (replAt r "2 * n" 5))
  shows "the block, from 144 to the end of the next line"
    (← drag r (replAt r "144") (replAt r "> List.range 30" 15))
  let list ← drag r (replAt r "[0, 1") (replAt r "29]" 3)
  let (lx, ly) := replAt r "[0, 1"
  let rows := (r.layout r.size.1 r.size.2).rows.filter (·.part == (r.pointAt lx ly).part)
  IO.println s!"  the list, over its {rows.length} rows: {list.selected.length} characters, \
    {(list.selected.splitOn "\n").length} line, ends {(list.selected.drop 100).toString.quote}"
  shows "from the end of the list into the line" (← drag r (replAt r "29]") (replAt r "> twice" 7))
  let low ← drag r (replAt r "> List.range 30") (300, 1000)
  IO.println s!"  from the last line entered to below the rows: \
    {(low.selected.splitOn "\n").map (·.take 20 |>.toString)}"
  -- Keys: typing ends the selection; Ctrl+C and Ctrl+Shift+C with
  -- nothing selected; with a run going.
  let typed ← hearNow svc out (.text "!")
  IO.println s!"  \"!\" typed with 144 selected: {typed.line.text.quote}, selected {typed.selected.quote}"
  IO.println s!"  nothing selected: Ctrl+C {asks r ctrlC}; Ctrl+Shift+C {asks r ctrlShiftC}"
  let running := { out with waiting := some { tag := 7 } }
  let some (copied, _) := running.heard ctrlC | throw (IO.userError "Ctrl+C did nothing")
  IO.println s!"  a run going, 144 selected: Ctrl+C {asks running ctrlC}; again {asks copied ctrlC}"
  -- On the desktop: lines typed into the REPL, a drag from 144 to the
  -- end of the list, and Ctrl+C, which asks the loop to copy.
  let (d, _) ← typedInRepl svc start ["def sq (n : Nat) := n * n", "sq 12", "List.range 30"]
  let some w := winTitled d "REPL" | throw (IO.userError "no REPL")
  let spots := (w.app.view w.bodyW w.bodyH).monoSpots
  let some (ax, ay, _) := spots.find? (·.2.2 == "144") | throw (IO.userError "no 144")
  let some (zx, zy, zs) := spots.find? (·.2.2.endsWith "29]") | throw (IO.userError "no 29]")
  let (ax, ay) := (w.bodyX + ax, w.bodyY + ay - 4)
  let (zx, zy) := (w.bodyX + zx + monoAdvance replFont * zs.length.toFloat, w.bodyY + zy - 4)
  let d := steps d (dragBy ax ay (zx - ax) (zy - ay))
  render c d.view; shot c "copy-repl.png"
  let (d, asked) := (steps d [.key (.char 'c') { ctrl := true }]).takeAsked
  IO.println s!"  on the desktop, a drag from 144 to the end of the list, Ctrl+C: \
    {asked.map (·.request.show)}"
  let (_, asked) := (steps d [.key (.char 'c') { ctrl := true }]).takeAsked
  IO.println s!"    Ctrl+C again: {asked.map (·.request.show)}"
  -- Clicks in the line move its cursor, and what's typed goes in there.
  -- A drag in the line selects, and leaves the cursor where it pressed.
  let clicked (r : Repl) (p : Float × Float) : IO Repl :=
    [.press p.1 p.2, .release p.1 p.2].foldlM (hearNow svc) r
  let cursor (r : Repl) := s!"{r.line.text.quote}, cursor at {r.line.cursor}"
  let c1 ← clicked r (replAt r "> twice" 3)
  IO.println s!"  a click after the t of twice: {cursor c1}; \"x\" typed: \
    {cursor (← hearNow svc c1 (.text "x"))}"
  let block ← [ctrlC, .paste "def f (n : Nat) :=\n  n + 1"].foldlM (hearNow svc) c1
  let c2 ← clicked block (replAt block "n + 1")
  IO.println s!"  a block in the line, a click before n + 1: cursor at {c2.line.cursor}; \
    \"2 * \" typed: {(← hearNow svc c2 (.text "2 * ")).line.text.quote}"
  let d2 ← drag block (replAt block "> def f" 6) (replAt block "> def f" 10)
  IO.println s!"  a drag in the line: {d2.selected.quote}, cursor at {d2.line.cursor}"
  let offered ← [ctrlC, .text "List.ma", key .tab].foldlM (hearNow svc) r
  let o ← clicked offered (replAt offered "mapA")
  IO.println s!"  a click on what Tab offered: {cursor o}, \
    {if o.offer.isSome then "still offered" else "no offer"}"
  let short ← [AppEvent.tick ⟨10, 8, 30⟩, .text "1 + 2", key .home].foldlM (hearNow svc) {}
  IO.println s!"  a REPL with only its line, Home, then a click below it: \
    {cursor (← clicked short (300, 250))}"
  -- On the desktop: "abc xyz" typed into the REPL (one run, both
  -- names), a click before `xyz`, and "X " typed there.
  let d ← stepNow svc d (.text "abc xyz")
  let some w := winTitled d "REPL" | throw (IO.userError "no REPL")
  let some (x, y, _) := (w.app.view w.bodyW w.bodyH).monoSpots.find? (·.2.2 == "abc xyz")
    | throw (IO.userError "no abc xyz")
  let (x, y) := (w.bodyX + x + monoAdvance replFont * 4, w.bodyY + y - 4)
  let d := steps d (click x y)
  render c d.view; shot c "repl-click.png"
  IO.println s!"  on the desktop, \"abc xyz\" typed, a click before xyz, \"X \" typed: \
    {(replLine (steps d [.text "X "])).quote}"

end LeanMachine.Tests
