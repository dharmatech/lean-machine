import Tests.ReplCopy

/-! # `--test`: scrolling the REPL back

A REPL alone, twenty lines evaluated at once, more than its view
holds: the wheel back, to the top and on again, a touchpad's halves,
PageUp, PageDown and Shift+PageUp; a run that ends while it's scrolled
back, and a key typed then. A selection made up there and copied, and
drags past the top and the bottom of the rows, which scroll. On the
desktop, the same lines, the wheel over the REPL, a drag and Ctrl+C
(docs/design/lean/scrolling-back.md). -/

namespace LeanMachine.Tests

-- The first and last rows the REPL shows, as drawn, and whether its
-- cursor is in view.
def replEnds (r : Repl) : String :=
  let l := r.layout r.size.1 r.size.2
  let first := (l.rows.head?.map (rowText ·.row)).getD ""
  let last := (l.rows.getLast?.map (rowText ·.row)).getD ""
  s!"{first.quote} to {last.quote}{if l.cursor.isSome then ", the cursor in view" else ""}"

def testReplScroll (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "scrolling the REPL back:"
  let key (k : Key) : AppEvent := .key k {}
  let lines := (List.range 20).map (s!"{· + 1} * 111")
  -- A REPL alone: twenty lines and what they came to, forty rows, and
  -- a line being typed; the view holds fourteen.
  let r ← hearNow svc {} (.tick ⟨10, 8, 30⟩)
  let r ← (lines.flatMap fun l => [AppEvent.text l, key .enter]).foldlM (hearNow svc) r
  let r ← hearNow svc r (.text "x")
  let ed (r : Repl) (evs : List AppEvent) : IO Repl := evs.foldlM (hearNow svc) r
  let shows (what : String) (r : Repl) : IO Unit := IO.println s!"  {what}: {replEnds r}"
  shows "following the newest rows" r
  let back ← ed r [.wheel 100 100 1]
  shows "the wheel a step back" back
  let top ← ed back [.wheel 100 100 100]
  shows "and 100 more" top
  shows "then a step on" (← ed top [.wheel 100 100 (-1)])
  shows "from a step back, a step on" (← ed back [.wheel 100 100 (-1)])
  shows "half a step back, twice" (← ed r [.wheel 100 100 0.5, .wheel 100 100 0.5])
  let pg ← ed r [key .pageUp]
  shows "PageUp" pg
  shows "then PageDown" (← ed pg [key .pageDown])
  shows "Shift+PageUp twice" (← ed r [.key .pageUp { shift := true }, .key .pageUp { shift := true }])
  -- A run that ends while the view is scrolled back, and a key typed.
  let ended ← ed { back with waiting := some { tag := 99 } } [.done 99 (.value "came back") 0]
  shows "a run ends while scrolled back" ended
  shows "then \"y\" typed" (← ed ended [.text "y"])
  -- Selecting up there, and drags past the top and the bottom of the rows.
  let drag (r : Repl) (a z : Float × Float) : IO Repl :=
    ed r [.press a.1 a.2, .motion z.1 z.2, .release z.1 z.2]
  let sel ← drag top (replAt top "222") (replAt top "222" 3)
  IO.println s!"  at the top, a drag over 222, Ctrl+C: \
    {((sel.heard (.key (.char 'c') { ctrl := true })).map (·.2.map (·.show))).getD []}, \
    then {replEnds sel}"
  let (ax, ay) := replAt r "2220"
  let up ← ed r ([.press ax ay] ++ List.replicate 5 (.motion 50 (-40)) ++ [.release 50 (-40)])
  let picked := up.selected.splitOn "\n"
  IO.println s!"  from 2220, five motions above the rows: {replEnds up}; \
    {picked.length} lines selected, from {(picked.head?.getD "").quote}"
  let (ax, ay) := replAt top "222"
  let down ← ed top ([.press ax ay] ++ List.replicate 4 (.motion 50 400) ++ [.release 50 400])
  IO.println s!"  from 222 at the top, four motions below the rows: {replEnds down}; \
    {(down.selected.splitOn "\n").length} lines selected"
  -- On the desktop: the same lines typed into the REPL, the wheel over
  -- it to the top and a step on, a drag over what came back from
  -- `2 * 111` and `3 * 111`, and Ctrl+C.
  let (d, _) ← typedInRepl svc start lines
  let some w := winTitled d "REPL" | throw (IO.userError "no REPL")
  let d := steps d [.wheel (w.bodyX + 200) (w.bodyY + 100) 100,
    .wheel (w.bodyX + 200) (w.bodyY + 100) (-1)]
  let some w := winTitled d "REPL" | throw (IO.userError "no REPL")
  let spots := (w.app.view w.bodyW w.bodyH).monoSpots
  let some (ax, ay, _) := spots.find? (·.2.2 == "222") | throw (IO.userError "no 222")
  let some (zx, zy, zs) := spots.find? (·.2.2 == "333") | throw (IO.userError "no 333")
  let (ax, ay) := (w.bodyX + ax, w.bodyY + ay - 4)
  let (zx, zy) := (w.bodyX + zx + monoAdvance replFont * zs.length.toFloat, w.bodyY + zy - 4)
  let d := steps d (dragBy ax ay (zx - ax) (zy - ay))
  render c d.view; shot c "repl-scroll.png"
  let (d, asked) := (steps d [.key (.char 'c') { ctrl := true }]).takeAsked
  IO.println s!"  on the desktop, the wheel over the REPL to the top and a step on, a drag \
    from 222 to 333, \
    Ctrl+C: {asked.map (·.request.show)}"
  let d := steps d [.text "1"]
  let shown := ((winTitled d "REPL").map (·.texts)).getD []
  IO.println s!"    then \"1\" typed: the last rows {(shown.drop (shown.length - 3))}"

end LeanMachine.Tests
