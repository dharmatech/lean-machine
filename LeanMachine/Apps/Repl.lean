import LeanMachine.Text

/-! # REPL: Lean, a line at a time

Enter asks the loop to evaluate the line in the REPL's Lean, on a thread
of its own, and what Lean said goes in the transcript when it comes back,
with the REPL's Lean after the line. That Lean is a value in the REPL's
state, so each REPL has its own, and undo takes definitions back with
the rest. The line can be edited meanwhile, and Ctrl+C stops the run. Up
and Down recall earlier lines. The line may hold several: a paste
(Ctrl+V) brings them, Shift+Enter starts a new one, Up and Down move
among them before they recall, and Enter evaluates them all, as one
source. The line, and every line entered, is
coloured by the tokens the REPL's Lean reads in it, and Tab completes
the name before the cursor from the names that Lean has. A press and a
drag select what the REPL shows, and Ctrl+C copies it; the wheel,
PageUp and PageDown scroll back through it. Pure: the REPL
only asks, and its Lean is a value with pure functions for both.
Everything is monospace, so where a character or the cursor goes is
arithmetic on `monoAdvance`. -/

namespace LeanMachine

/-! ## The REPL -/

inductive Entry where
  | note (s : String)     -- from the REPL itself
  -- A line entered, shown after the prompt, with its tokens as the
  -- REPL's Lean read them then.
  | input (s : String) (tokens : Array Token := #[])
  | output (s : String)   -- what came back; it may span lines
  | warning (s : String)
  | error (s : String)
  deriving Repr

-- What an entry says; for a line entered, without its prompt.
def Entry.text : Entry → String
  | .note s | .input s _ | .output s | .warning s | .error s => s

def Entry.isInput : Entry → Bool
  | .input .. => true
  | _ => false

-- Parts of what the REPL shows, in order: the entries of the transcript,
-- each by its place counted from the oldest, so it stays put as entries
-- come, then the line being edited (`none`).
def partLt : Option Nat → Option Nat → Bool
  | some i, some j => i < j
  | some _, none => true
  | none, _ => false

-- A place between two characters of what the REPL shows: in a part, and
-- how many characters into it.
structure Spot where
  part : Option Nat
  at_ : Nat
  deriving BEq, Repr, Inhabited

def Spot.lt (a b : Spot) : Bool :=
  partLt a.part b.part || (a.part == b.part && a.at_ < b.at_)

-- Does a selection from `a` to `z` take along the prompt of a line that
-- starts at `s`? Only when it goes past one part, and has that start.
def leadTaken (a z s : Spot) : Bool := a.part != z.part && !s.lt a && s.lt z

-- The run the REPL is waiting for.
structure Waiting where
  tag : Nat
  stopping : Bool := false   -- Ctrl+C asked it to stop
  deriving Inhabited

-- The run that fetches the desktop's own Lean, for a REPL that has
-- none yet: an empty line evaluated in it.
def leanTag : Nat := 0

def replSize : Float × Float := (560, 300)   -- a new REPL's body

structure Repl where
  line : Line := {}
  tokens : Array Token := #[]     -- the line's, as the REPL's Lean reads it
  offer : Option Offer := none    -- what Tab found, until the line changes
  transcript : List Entry := []   -- newest first
  history : List String := []     -- lines entered, newest first
  back : Nat := 0                 -- how far back in the history the line is
  draft : String := ""            -- the line being typed, kept while Up goes back
  waiting : Option Waiting := none
  nextTag : Nat := leanTag + 1
  env : Option Env := none        -- the REPL's Lean; `none`: the desktop's own
  askedLean : Option TimeOfDay := none  -- the tick it last asked for that in
  -- Where a press was, and where the pointer is now: what's selected
  -- runs between them.
  selecting : Option (Spot × Spot) := none
  dragging : Bool := false        -- a press, not released yet
  -- The body's size, as the window last said it: a press needs it, to
  -- find the row it's on, and the wheel, to count rows.
  size : Float × Float := replSize
  -- Scrolled back, the view's top row: an entry, counted from the
  -- oldest, and which of its rows. `none`: the view follows the newest
  -- rows.
  top : Option (Nat × Nat) := none
  wheelRest : Float := 0          -- a touchpad's fraction of a row, not scrolled yet

namespace Repl

def edit (r : Repl) (f : Line → Line) : Repl := { r with line := f r.line }

-- The selection, its first end first, unless its ends are the same.
def selection (r : Repl) : Option (Spot × Spot) := do
  let (m, p) ← r.selecting
  if m == p then none else some (if m.lt p then (m, p) else (p, m))

-- The line's tokens, read again by the REPL's Lean: after anything that
-- may change the line or the Lean. None until the REPL has its Lean.
def relex (r : Repl) : Repl :=
  { r with tokens := (r.env.map (·.tokens r.line.text)).getD #[] }

-- A REPL with no Lean of its own yet asks for the desktop's, at most
-- once a second while it has none (an undo may bring back a REPL whose
-- answer went to a world that's gone).
def askLean (r : Repl) (t : TimeOfDay) : Option (Repl × List Request) :=
  if r.env.isNone && r.askedLean != some t then
    some ({ r with askedLean := some t }, [.eval leanTag "" none])
  else none

-- The line goes to the transcript and to the history, unless it's empty
-- or the same as the last one, and the REPL asks for it to be evaluated.
-- While a run is going, Enter does nothing.
def enter (r : Repl) : Option (Repl × List Request) :=
  if r.waiting.isSome then none else
  let s := r.line.text
  let r := { r with line := {}, back := 0, draft := "",
                    transcript := .input s r.tokens :: r.transcript,
                    history := if s.isEmpty || r.history.head? == some s then r.history
                               else s :: r.history }
  if s.isEmpty then some (r, [])
  else some ({ r with waiting := some { tag := r.nextTag }, nextTag := r.nextTag + 1 },
             [.eval r.nextTag s r.env])

-- Ctrl+C: stops the run, or with none going, clears the line.
def interrupt (r : Repl) : Option (Repl × List Request) :=
  match r.waiting with
  | some w => some ({ r with waiting := some { w with stopping := true } }, [.stop w.tag])
  | none => some ({ r with line := {}, back := 0, draft := "" }, [])

def took (ms : Nat) : String :=
  if ms < 1000 then s!"{ms} ms"
  else s!"{ms / 1000}.{(ms % 1000) / 100} s"

-- How a run stopped: Lean saw the stop and unwound, through any
-- `finally`, or a safepoint cut the run off, past the Lean code on the way.
def stoppedNote (ms : Nat) (cleanly : Bool) : String :=
  if ms == 0 then "stopped"
  else if cleanly then s!"interrupted after {took ms}, through any `finally`"
  else s!"cut off after {took ms}, past any `finally`"

def Said.entry : Said → Entry
  | .info s => .output s
  | .warning s => .warning s
  | .error s => .error s

-- The outcome of the run the REPL is waiting for goes in the transcript,
-- and the Lean after the line becomes the REPL's. Outcomes of other runs
-- (from before an undo, say) don't matter to it.
def ended (r : Repl) (tag : Nat) (o : Outcome) (ms : Nat) : Option Repl :=
  match r.waiting with
  | some w =>
    if w.tag != tag then none else
    let didn'tStop : List Entry :=
      if w.stopping then [.note "it didn't stop: nothing on its way was a safepoint"]
      else []
    let timing : List Entry := if ms ≥ 100 then [.note s!"took {took ms}"] else []
    -- In the order they're read.
    let (entries, env) : List Entry × Option Env := match o with
      | .value s => (.output s :: didn'tStop ++ timing, r.env)
      | .evaluated said env => (said.map Said.entry ++ didn'tStop ++ timing, some env)
      | .stopped said cleanly =>
        (said.map Said.entry ++ [.note (stoppedNote ms cleanly)], r.env)
      | .failed why => ([.error s!"failed: {why}"], r.env)
      -- The REPL asks for no files, and reloads none.
      | .read _ | .wrote | .listed _ | .reloaded .. => ([], r.env)
    some { r with waiting := none, env, transcript := entries.reverse ++ r.transcript }
  | none => none

-- The line `n` back in the history; 0 is the line that was being typed.
def goBack (r : Repl) (n : Nat) : Repl :=
  let draft := if r.back == 0 then r.line.text else r.draft
  let text := if n == 0 then draft else r.history.getD (n - 1) ""
  { r with back := n, draft, line := .ofString text }

-- Edits that ask for nothing. Home and End go to the start and end of
-- the cursor's own line; Up and Down go to the line above or below it,
-- and from the first or the last, back and forth in the history.
def editKey (r : Repl) : Key → Option Repl
  | .backspace => some (r.edit Line.backspace)
  | .delete => some (r.edit Line.delete)
  | .left => some (r.edit Line.left)
  | .right => some (r.edit Line.right)
  | .home => some (r.edit Line.lineStart)
  | .«end» => some (r.edit Line.lineEnd)
  | .up =>
    match r.line.up with
    | some l => some { r with line := l }
    | none => if r.back < r.history.length then some (r.goBack (r.back + 1)) else none
  | .down =>
    match r.line.down with
    | some l => some { r with line := l }
    | none => if r.back > 0 then some (r.goBack (r.back - 1)) else none
  | _ => none

-- Shift+Enter: a new line in the line, as far in as the cursor's, and
-- two more after `:=`, `do` and the like.
def newLine (r : Repl) : Repl :=
  let pad := String.ofList (List.replicate (indentAfter r.line.own r.line.column) ' ')
  r.edit (·.insert ("\n" ++ pad))

-- Is the cursor in a string, a comment, or where the tokenizer gave up?
def inText (r : Repl) : Bool := LeanMachine.inText r.tokens r.line.cursor

-- Tab: the name before the cursor, finished as far as every name it
-- could become agrees, from the REPL's Lean. When it could become more
-- than one, they're offered under the line until it changes.
def tab (r : Repl) : Option Repl := do
  let env ← r.env
  let word := wordBefore r.line.before
  if word.isEmpty || r.inText then none
  let names := (env.complete word).toList
  let more := String.ofList ((commonPrefix names).toList.drop word.length)
  let r := if more.isEmpty then r else r.edit (·.insert more)
  some { r with offer := if names.length == 1 then none else some { word, names } }

end Repl

/-! ## How it looks -/

def replFont : Float := 15     -- monoAdvance 15 = 9 pixels a column
def replLineH : Float := 20
def replPad : Float := 10
def prompt : String := "> "
def promptRgb : UInt32 := 0x7aa2f7

-- Where each of the lines in `cs` starts and stops, "\n" between them.
def lineSpans (cs : Array Char) : List (Nat × Nat) :=
  let (spans, start) := (List.range cs.size).foldl (init := ([], 0)) fun (spans, start) i =>
    if cs[i]! == '\n' then ((start, i) :: spans, i + 1) else (spans, start)
  ((start, cs.size) :: spans).reverse

#guard lineSpans "ab\n\ncd".toList.toArray == [(0, 2), (3, 3), (4, 6)]

-- What a row shows of a text cut into rows: its characters from `lo`
-- to `hi`, after `lead` columns of prompt (or spaces as wide), and
-- whether it's the last row of one of the text's own lines, so that
-- a "\n" comes after it, or the next part.
structure Span where
  lo : Nat := 0
  hi : Nat := 0
  lead : Nat := 0
  ends : Bool := false
  deriving BEq, Repr

-- `s` in rows of `cols`, each character in its colour from `rgbs`. Each
-- of its own lines starts its own rows, the first after `lead`, the
-- rest after as many spaces, so their indents line up. Each row comes
-- with what it shows of `s`.
def spannedRows (cols : Nat) (s : String) (rgbs : Array UInt32) (lead : String := "") :
    List (Row × Span) :=
  let cs := s.toList.toArray
  (lineSpans cs).zipIdx.flatMap fun ((lo, hi), i) =>
    let ld := if i == 0 then lead else "".pushn ' ' lead.length
    let rows := runRows cols (ld.toList.toArray ++ cs.extract lo hi)
      (Array.replicate ld.length promptRgb ++ rgbs.extract lo hi)
    -- How many characters of `s` are before column `j` of the line's
    -- rows, counted on from row to row.
    let at_ (j : Nat) := min hi (lo + (j - ld.length))
    rows.zipIdx.map fun (row, k) =>
      (row, { lo := at_ (k * cols), hi := at_ ((k + 1) * cols),
              lead := if k == 0 then ld.length else 0, ends := k + 1 == rows.length })

#guard (spannedRows 10 "ab\n12345678901" (Array.replicate 14 0) "> ").map (·.2) ==
  [⟨0, 2, 2, true⟩, ⟨3, 11, 2, false⟩, ⟨11, 14, 0, true⟩]
#guard (spannedRows 4 "" #[]).map (·.2) == [⟨0, 0, 0, true⟩]

-- How many rows of `cols` a line of `n` characters after the prompt takes.
def rowsFor (cols n : Nat) : Nat := max 1 ((prompt.length + n + cols - 1) / cols)

-- Where the cursor goes among the line's rows: its row and column. At the
-- end of a full row, in the last line, it starts the next row; in a
-- line before it, it stays at the end of that row.
def promptCursor (cols : Nat) (s : String) (cursor : Nat) : Nat × Nat :=
  let spans := lineSpans s.toList.toArray
  let k := spans.findIdx fun (_, hi) => cursor ≤ hi
  let above := ((spans.take k).map fun (lo, hi) => rowsFor cols (hi - lo)).sum
  let (lo, hi) := spans.getD k (0, 0)
  let p := prompt.length + cursor - lo
  if p / cols < rowsFor cols (hi - lo) || k + 1 == spans.length then (above + p / cols, p % cols)
  else (above + rowsFor cols (hi - lo) - 1, cols)

#guard promptCursor 10 "abc" 3 == (0, 5)
#guard promptCursor 10 "12345678" 8 == (1, 0)
#guard promptCursor 10 "ab\ncdef" 5 == (1, 4)
#guard promptCursor 10 "12345678\nx" 8 == (0, 10)

-- An entry in rows: a line entered after the prompt, coloured by its
-- tokens; the rest in a colour for each kind.
def Entry.rows (cols : Nat) (e : Entry) : List (Row × Span) :=
  let s := e.text
  let inOne (rgb : UInt32) := spannedRows cols s (Array.replicate s.length rgb)
  match e with
  | .input _ tokens => spannedRows cols s (tokenColours s.length tokens) prompt
  | .output _ => inOne 0x9ece6a
  | .note _ => inOne 0x565f89
  | .warning _ => inOne 0xe0af68
  | .error _ => inOne 0xf7768e

-- How many rows `Entry.rows` cuts an entry into, without cutting it.
def Entry.rowCount (cols : Nat) (e : Entry) : Nat :=
  let lead := if e.isInput then prompt.length else 0
  ((lineSpans e.text.toList.toArray).map fun (lo, hi) =>
    max 1 ((lead + (hi - lo) + cols - 1) / cols)).sum

#guard [Entry.input "ab\n12345678901", .output "", .output "x\n\n123456789012345"].all
  fun e => e.rowCount 10 == (e.rows 10).length

-- A row of the view: what it draws, and what it shows of the REPL's
-- text, in which part; and for a row of an entry, which entry and which
-- of its rows.
structure Shown where
  row : Row
  part : Option Nat
  span : Span
  entryRow : Option (Nat × Nat) := none

-- What the view shows at a width and height: its rows, top to bottom,
-- the cursor's row among them and its column (none: scrolled out of
-- view), and the columns a row has.
structure Layout where
  rows : List Shown
  cursor : Option (Nat × Nat)
  cols : Nat

-- How many columns, and rows, a body this wide, or high, has room for.
def replCols (w : Float) : Nat := max 4 ((w - 2 * replPad) / monoAdvance replFont).floor.toUInt64.toNat
def replFits (h : Float) : Nat := max 1 ((h - 2 * replPad) / replLineH).floor.toUInt64.toNat

-- The transcript, then a row that says a run is going, then the line
-- being edited and the cursor in it, then what Tab offered. Long lines
-- wrap. When it all doesn't fit, the oldest rows go off the top, so the
-- newest stay in view, and the cursor's row with them. The rows that
-- show none of the text are on the end of the newest entry (a run's
-- row) or of the line (what Tab offered). Scrolled back, the view
-- starts at its top row and goes on as far as it fits, so the line and
-- the cursor may be below it.
def Repl.layout (r : Repl) (w h : Float) : Layout :=
  let cols := replCols w
  let fits := replFits h
  let s := r.line.text
  let n := s.length
  -- Where the cursor is, among the rows of the line.
  let (cRow, cCol) := promptCursor cols s r.line.cursor
  let editing := (spannedRows cols s (tokenColours n r.tokens) prompt).map fun (row, span) =>
    ({ row, part := none, span } : Shown)
  let lineEnd : Span := { lo := n, hi := n }
  let editing := if cRow < editing.length then editing
    else editing ++ [{ row := [], part := none, span := lineEnd }]
  let count := r.transcript.length
  let status : List Shown := match r.waiting with
    | some w =>
      let newest := (r.transcript.head?.map (·.text.length)).getD 0
      (lines (if w.stopping then "stopping…" else "running… Ctrl+C stops it") 0xe0af68 cols).map
        ({ row := ·, part := if count > 0 then some (count - 1) else none,
           span := { lo := newest, hi := newest } })
    | none => []
  let offered : List Shown := match r.offer with
    | some o => (o.rows cols).map ({ row := ·, part := none, span := lineEnd })
    | none => []
  let below := status ++ editing ++ offered
  let entryRows (e : Entry) (j : Nat) : List Shown :=
    (e.rows cols).zipIdx.map fun ((row, span), k) =>
      { row, part := some j, span, entryRow := some (j, k) }
  -- Only the newest entries are cut into rows: enough to fill the view.
  -- The `i`th newest is the `count - 1 - i`th from the oldest.
  let rec newest (es : List Entry) (i : Nat) (rows : List Shown) (k : Nat) : List Shown :=
    match es with
    | e :: rest =>
      if k ≥ fits then rows
      else
        let rs := entryRows e (count - 1 - i)
        newest rest (i + 1) (rs ++ rows) (k + rs.length)
    | [] => rows
  -- After `rows`, the rows of the entries `es` (from entry `j`, oldest
  -- first), then `below`, as many as fill the view; and where `below`
  -- starts among them, if they get that far.
  let rec onward (es : List Entry) (j : Nat) (rows : List Shown) : List Shown × Option Nat :=
    if rows.length ≥ fits then (rows, none) else
    match es with
    | e :: rest => onward rest (j + 1) (rows ++ entryRows e j)
    | [] => (rows ++ below, some rows.length)
  let follow (_ : Unit) : Layout :=
    let all := newest r.transcript 0 below below.length
    -- The oldest rows go, but never the cursor's: a line taller than the
    -- view shows from the cursor's row down.
    let cursorAt := all.length - offered.length - editing.length + cRow
    let gone := min (all.length - fits) cursorAt
    { rows := (all.drop gone).take fits, cursor := some (cursorAt - gone, cCol), cols }
  match r.top with
  | none => follow ()
  | some (j, k) =>
    match (r.transcript.take (count - j)).reverse with
    | [] => follow ()
    | e :: rest =>
      -- A row the window's size has since taken away is the entry's last.
      let first := entryRows e j
      let (rows, belowAt) := onward rest (j + 1) (first.drop (min k (first.length - 1)))
      -- Short of filling the view, it would show the newest rows anyway.
      if rows.length < fits then follow () else
      let cursor := belowAt.bind fun b =>
        let c := b + status.length + cRow
        if c < fits then some (c, cCol) else none
      { rows := rows.take fits, cursor, cols }

-- The columns of a row that are selected, from `a` to `z`, if any: its
-- characters between them; its prompt too, when the selection takes it
-- along; and a column more, for its line's end, when the selection goes
-- on past that.
def Shown.selectedCols (v : Shown) (a z : Spot) (cols : Nat) : Option (Nat × Nat) :=
  let here (n : Nat) : Spot := { part := v.part, at_ := n }
  let ⟨lo, hi, lead, ends⟩ := v.span
  let within (s : Spot) : Nat := if s.lt (here lo) then lo else if (here hi).lt s then hi else s.at_
  let c0 := if lead > 0 && leadTaken a z (here lo) then 0 else lead + (within a - lo)
  let c1 := lead + (within z - lo)
  let c1 := if ends && !(here hi).lt a && (here hi).lt z then min cols (c1 + 1) else c1
  if c0 < c1 then some (c0, c1) else none

-- The rows, a box behind what's selected of each, and the cursor.
def Repl.view (r : Repl) (w h : Float) : Picture :=
  let adv := monoAdvance replFont
  let l := r.layout w h
  let top (i : Nat) : Float := replPad + replLineH * i.toFloat
  let selected : List Picture := match r.selection with
    | some (a, z) => l.rows.zipIdx.filterMap fun (v, i) => do
      let (c0, c1) ← v.selectedCols a z l.cols
      some (.rect (replPad + adv * c0.toFloat) (top i) (adv * (c1 - c0).toFloat) replLineH 0
        selectedRgb)
    | none => []
  let cursor : List Picture := match l.cursor with
    | some (row, col) =>
      [.rect (replPad + adv * col.toFloat - 1) (top row + 2) 2 (replLineH - 4) 0 0xbb9af7]
    | none => []
  .group (selected ++ l.rows.zipIdx.flatMap (fun (v, i) =>
      v.row.map fun run =>
        .mono (replPad + adv * run.col.toFloat) (top i + 14) replFont run.rgb run.text) ++
    cursor)

/-! ## Scrolling back -/

-- The row `n` rows before row `k` of entry `j`, among the transcript's
-- rows, back through `before`, the entries before it, newest first; no
-- further than the first row.
def rowsBack (cols : Nat) : List Entry → Nat → Nat → Nat → Nat × Nat
  | [], j, k, n => (j, k - n)
  | e :: rest, j, k, n =>
    if n ≤ k then (j, k - n) else rowsBack cols rest (j - 1) (e.rowCount cols - 1) (n - k - 1)

-- The row `n` rows after row `k` of the first of `es`, entry `j`, on
-- through the rest, oldest first; `none` past the last.
def rowsOn (cols : Nat) : List Entry → Nat → Nat → Nat → Option (Nat × Nat)
  | [], _, _, _ => none
  | e :: rest, j, k, n =>
    let rk := e.rowCount cols
    if k + n < rk then some (j, k + n) else rowsOn cols rest (j + 1) 0 (k + n - rk)

-- Entry 1 is "a", a row; entry 0 is "b\nc", two.
#guard rowsBack 10 [.output "a", .output "b\nc"] 2 1 2 == (1, 0)
#guard rowsBack 10 [.output "a", .output "b\nc"] 2 1 3 == (0, 1)
#guard rowsBack 10 [.output "a", .output "b\nc"] 2 1 10 == (0, 0)
#guard rowsOn 10 [.output "a\nb", .output "c"] 4 1 1 == some (5, 0)
#guard rowsOn 10 [.output "a\nb", .output "c"] 4 1 2 == none

namespace Repl

-- Entry `j`, counted from the oldest.
def entryAt (r : Repl) (j : Nat) : Option Entry :=
  if j < r.transcript.length then r.transcript[r.transcript.length - 1 - j]? else none

-- The top row of the view that follows the newest rows, as an entry and
-- a row of it; or, when it shows none of the transcript, as if just
-- past its last entry.
def followTop (r : Repl) : Nat × Nat :=
  let l := { r with top := none }.layout r.size.1 r.size.2
  (l.rows.head? >>= (·.entryRow)).getD (r.transcript.length, 0)

-- The view scrolled back to start at `t`, or following the newest rows
-- again, if from `t` it would show them anyway.
def scrolledTo (r : Repl) (t : Nat × Nat) : Repl :=
  let (j, k) := r.followTop
  { r with top := if t.1 < j || (t.1 == j && t.2 < k) then some t else none }

-- The view `n` rows further back, no further than the first.
def scrollBack (r : Repl) (n : Nat) : Repl :=
  let cols := replCols r.size.1
  let (j, k) := r.top.getD r.followTop
  let k := match r.entryAt j with
    | some e => min k (e.rowCount cols - 1)
    | none => k
  r.scrolledTo (rowsBack cols (r.transcript.drop (r.transcript.length - j)) j k n)

-- The view `n` rows on, following the newest rows again when it gets to
-- them.
def scrollOn (r : Repl) (n : Nat) : Repl :=
  match r.top with
  | none => r
  | some (j, k) =>
    let es := (r.transcript.take (r.transcript.length - j)).reverse
    match rowsOn (replCols r.size.1) es j k n with
    | some t => r.scrolledTo t
    | none => { r with top := none }

-- The wheel scrolls three rows a step; a touchpad's fractions add up.
def wheel (r : Repl) (dy : Float) : Repl :=
  let total := r.wheelRest + 3 * dy
  let rows := if total ≥ 0 then total.floor else total.ceil
  let r := { r with wheelRest := total - rows }
  if rows > 0 then r.scrollBack rows.toUInt64.toNat
  else if rows < 0 then r.scrollOn (-rows).toUInt64.toNat
  else r

-- PageUp and PageDown: a page back or on, a row less than the view.
def page (r : Repl) (back : Bool) : Option (Repl × List Request) :=
  let n := replFits r.size.2 - 1
  let r' := if back then r.scrollBack (max 1 n) else r.scrollOn (max 1 n)
  if r'.top == r.top then none else some (r', [])

end Repl

/-! ## Selecting and copying -/

namespace Repl

-- What a press at (x, y) in the body is on: the place between two
-- characters nearest it, in the row it's on. Above the rows, the start
-- of the first; below them, the end of the last.
def pointAt (r : Repl) (x y : Float) : Spot :=
  let l := r.layout r.size.1 r.size.2
  let i := ((y - replPad) / replLineH).floor
  let col := ((x - replPad) / monoAdvance replFont).round
  let (i, col) := if i < 0 then (0, 0)
    else if i.toUInt64.toNat ≥ l.rows.length then (l.rows.length - 1, l.cols)
    else (i.toUInt64.toNat, if col < 0 then 0 else col.toUInt64.toNat)
  match l.rows[i]? with
  | some v => { part := v.part, at_ := min v.span.hi (v.span.lo + (col - v.span.lead)) }
  | none => { part := none, at_ := 0 }

-- Each part, oldest first: which, its text, and whether its lines are
-- led by a prompt.
def parts (r : Repl) : List (Option Nat × String × Bool) :=
  r.transcript.reverse.zipIdx.map (fun (e, i) => (some i, e.text, e.isInput)) ++
    [(none, r.line.text, true)]

-- What's selected, as it was written: a line that wraps is one line.
-- Within one part, its characters, so a line copied from a line entered
-- pastes back as it was. Past one part, the parts on lines of their own,
-- and each line entered whose start is selected led by its prompt (or
-- spaces as wide), so it reads as the REPL showed it.
def selected (r : Repl) : String :=
  match r.selection with
  | none => ""
  | some (a, z) =>
    let chars (s : String) (lo hi : Nat) : String := String.ofList ((s.toList.drop lo).take (hi - lo))
    let some_ := r.parts.filter fun (p, _) => !partLt p a.part && !partLt z.part p
    if a.part == z.part then
      match some_ with
      | [(_, s, _)] => chars s a.at_ z.at_
      | _ => ""
    else "\n".intercalate (some_.map fun (p, s, led) =>
      let lo := if p == a.part then a.at_ else 0
      let hi := if p == z.part then z.at_ else s.length
      if !led then chars s lo hi else
      let cs := s.toList.toArray
      "\n".intercalate ((lineSpans cs).zipIdx.filterMap fun ((ls, le), i) =>
        if hi < ls || le < lo then none else
        let lead := if !leadTaken a z { part := p, at_ := ls } then ""
          else if i == 0 then prompt else "".pushn ' ' prompt.length
        some (lead ++ String.ofList (cs.extract (max ls lo) (min le hi)).toList)))

-- Ctrl+C or Ctrl+Shift+C: what's selected goes on the clipboard, and the
-- selection ends, so that the next Ctrl+C stops a run again. Nothing
-- selected, nothing.
def copy (r : Repl) : Option (Repl × List Request) :=
  if r.selection.isNone then none
  else some ({ r with selecting := none, dragging := false }, [.copy r.selected])

/-! ## What it hears -/

-- Keys, typing and pastes. An edit or a key that isn't Tab takes the
-- offer away.
def keyed (r : Repl) : AppEvent → Option (Repl × List Request)
  | .text s => some ({ r with offer := none }.edit (·.insert s), [])
  -- A paste goes in the line, like typing, its lines and all; blank
  -- lines around them don't count.
  | .paste s =>
    let blank (l : String) := l.trimAscii.isEmpty
    match ((pastedLines s).dropWhile blank).reverse.dropWhile blank |>.reverse with
    | [] => none
    | ls => some ({ r with offer := none }.edit (·.insert ("\n".intercalate ls)), [])
  | .key .tab m => if m == {} then (r.tab).map (·, []) else none
  | .key .enter m =>
    if m == { shift := true } then some ({ r with offer := none }.newLine, [])
    else { r with offer := none }.enter
  | .key (.char 'c') m =>
    if m == { ctrl := true } then { r with offer := none }.interrupt else none
  | .key k _ => ({ r with offer := none }.editKey k).map (·, [])
  | _ => none

-- A press puts both ends of the selection where it lands, and a drag
-- moves the second to the pointer; above or below the rows, the view
-- scrolls a row for each motion. A key that does something ends the
-- selection, and brings the view back to the newest rows; Ctrl+C copies
-- the selection, and with nothing selected stops a run or clears the
-- line. Ctrl+Shift+C only copies. The wheel, PageUp and PageDown scroll.
def heard (r : Repl) (e : AppEvent) : Option (Repl × List Request) :=
  let typing := { r with selecting := none, dragging := false, top := none }
  match e with
  | .key (.char 'c') m =>
    if m == ctrlShift || (m == { ctrl := true } && r.selection.isSome) then r.copy
    else typing.keyed e
  | .key .pageUp m => if m == {} || m == { shift := true } then r.page true else none
  | .key .pageDown m => if m == {} || m == { shift := true } then r.page false else none
  | .wheel _ _ dy => some (r.wheel dy, [])
  | .press x y =>
    let s := r.pointAt x y
    some ({ r with selecting := some (s, s), dragging := true }, [])
  | .motion x y =>
    match r.selecting with
    | some (m, p) =>
      if !r.dragging then none else
      let r' := if y < replPad then r.scrollBack 1
        else if y ≥ replPad + replLineH * (replFits r.size.2).toFloat then r.scrollOn 1
        else r
      let s := r'.pointAt x y
      if s == p && r'.top == r.top then none else some ({ r' with selecting := some (m, s) }, [])
    | none => none
  | .release _ _ => if r.dragging then some ({ r with dragging := false }, []) else none
  | .resize w h => some ({ r with size := (w, h) }, [])
  | .done tag o ms =>
    if tag == leanTag then
      match o, r.env with
      | .evaluated _ env, none => some ({ r with env := some env }, [])
      | _, _ => none
    else (r.ended tag o ms).map (·, [])
  | .tick t => r.askLean t
  | _ => typing.keyed e

-- Other modifiers don't matter yet: Ctrl+Left is Left. Whatever changes
-- the REPL, the line's tokens are read again.
def step (r : Repl) (e : AppEvent) : Option (Repl × List Request) :=
  (r.heard e).map fun (r, asks) => (r.relex, asks)

end Repl

def repl : App :=
  App.asking "REPL"
    ({ transcript := [.note "Lean, with Init and the desktop's modules but its apps, \
         LeanMachine open. A line is commands, or a term to evaluate. `world` is the \
         desktop when you press Enter, its apps in `(← world).catalog`; `launch app` \
         opens an app. Ctrl+C stops a run. Up, Down: history. The wheel, PageUp: back. \
         Tab completes a name. \
         Ctrl+V pastes, lines and all; Shift+Enter starts a new line. A drag selects; \
         Ctrl+C copies it."] } : Repl)
    Repl.step Repl.view (size := replSize)

end LeanMachine
