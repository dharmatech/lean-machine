import LeanMachine.App

/-! # REPL: Lean, a line at a time

Enter asks the loop to evaluate the line in the REPL's Lean, on a thread
of its own, and what Lean said goes in the transcript when it comes back,
with the REPL's Lean after the line. That Lean is a value in the REPL's
state, so each REPL has its own, and undo takes definitions back with
the rest. The line can be edited meanwhile, and Ctrl+C stops the run. Up
and Down recall earlier lines. The line, and every line entered, is
coloured by the tokens the REPL's Lean reads in it, and Tab completes
the name before the cursor from the names that Lean has. Pure: the REPL
only asks, and its Lean is a value with pure functions for both.
Everything is monospace, so where a character or the cursor goes is
arithmetic on `monoAdvance`. -/

namespace LeanMachine

/-! ## The line being edited -/

-- The characters before the cursor, nearest first, and those after it.
-- Every edit takes or adds a character at the head of one of them.
structure Line where
  before : List Char := []
  after : List Char := []
  deriving Inhabited

namespace Line

-- `s`, with the cursor at its end.
def ofString (s : String) : Line := { before := s.toList.reverse }

def chars (l : Line) : List Char := l.before.reverse ++ l.after
def text (l : Line) : String := String.ofList l.chars

-- The cursor's column: how many characters are before it.
def cursor (l : Line) : Nat := l.before.length

def insert (l : Line) (s : String) : Line :=
  { l with before := s.toList.reverse ++ l.before }

def backspace (l : Line) : Line := { l with before := l.before.drop 1 }
def delete (l : Line) : Line := { l with after := l.after.drop 1 }

def left (l : Line) : Line :=
  match l.before with
  | c :: cs => { before := cs, after := c :: l.after }
  | [] => l

def right (l : Line) : Line :=
  match l.after with
  | c :: cs => { before := c :: l.before, after := cs }
  | [] => l

def toStart (l : Line) : Line := { before := [], after := l.chars }
def toEnd (l : Line) : Line := { before := l.after.reverse ++ l.before, after := [] }

end Line

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

-- What Tab found for the name before the cursor: what it could become
-- (none: nothing here starts with it).
structure Offer where
  word : String
  names : List String

-- The run the REPL is waiting for.
structure Waiting where
  tag : Nat
  stopping : Bool := false   -- Ctrl+C asked it to stop
  deriving Inhabited

-- The run that fetches the desktop's own Lean, for a REPL that has
-- none yet: an empty line evaluated in it.
def leanTag : Nat := 0

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

namespace Repl

def edit (r : Repl) (f : Line → Line) : Repl := { r with line := f r.line }

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
    some { r with waiting := none, env, transcript := entries.reverse ++ r.transcript }
  | none => none

-- The line `n` back in the history; 0 is the line that was being typed.
def goBack (r : Repl) (n : Nat) : Repl :=
  let draft := if r.back == 0 then r.line.text else r.draft
  let text := if n == 0 then draft else r.history.getD (n - 1) ""
  { r with back := n, draft, line := .ofString text }

-- Edits that ask for nothing.
def editKey (r : Repl) : Key → Option Repl
  | .backspace => some (r.edit Line.backspace)
  | .delete => some (r.edit Line.delete)
  | .left => some (r.edit Line.left)
  | .right => some (r.edit Line.right)
  | .home => some (r.edit Line.toStart)
  | .«end» => some (r.edit Line.toEnd)
  | .up => if r.back < r.history.length then some (r.goBack (r.back + 1))
           else none
  | .down => if r.back > 0 then some (r.goBack (r.back - 1)) else none
  | _ => none

-- The name before the cursor, as far back as there are characters a
-- name can have, dots included: `Nat.su` in `(Nat.su`. Empty unless it
-- starts the way a name does (not `.1`, `3.5` or `x.`'s field).
def wordBefore (before : List Char) : String :=
  match (before.takeWhile fun c => Lean.isIdRest c || c == '.').reverse with
  | c :: cs => if Lean.isIdFirst c then String.ofList (c :: cs) else ""
  | [] => ""

-- Is the cursor in a string, a comment, or where the tokenizer gave up?
def inText (r : Repl) : Bool :=
  let at_ := r.line.cursor
  r.tokens.any fun t =>
    t.start < at_ && at_ ≤ t.stop && [.string, .comment, .error].contains t.kind

def commonPrefix : List String → String
  | [] => ""
  | s :: rest => rest.foldl (init := s) fun a b =>
      String.ofList (((a.toList.zip b.toList).takeWhile fun (x, y) => x == y).map (·.1))

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

-- An edit or a key that isn't Tab takes the offer away.
def heard (r : Repl) : AppEvent → Option (Repl × List Request)
  | .text s => some ({ r with offer := none }.edit (·.insert s), [])
  | .key .tab m => if m == {} then (r.tab).map (·, []) else none
  | .key .enter _ => { r with offer := none }.enter
  | .key (.char 'c') m =>
    if m == { ctrl := true } then { r with offer := none }.interrupt else none
  | .key k _ => ({ r with offer := none }.editKey k).map (·, [])
  | .done tag o ms =>
    if tag == leanTag then
      match o, r.env with
      | .evaluated _ env, none => some ({ r with env := some env }, [])
      | _, _ => none
    else (r.ended tag o ms).map (·, [])
  | .tick t => r.askLean t
  | _ => none

-- Other modifiers don't matter yet: Ctrl+Left is Left. Whatever changes
-- the REPL, the line's tokens are read again.
def step (r : Repl) (e : AppEvent) : Option (Repl × List Request) :=
  (r.heard e).map fun (r, asks) => (r.relex, asks)

end Repl

/-! ## How it looks -/

def replFont : Float := 15     -- monoAdvance 15 = 9 pixels a column
def replLineH : Float := 20
def replPad : Float := 10
def prompt : String := "> "
def promptRgb : UInt32 := 0x7aa2f7
def plainRgb : UInt32 := 0xc0caf5

-- Tokyo Night's colours for Lean's tokens.
def TokenKind.rgb : TokenKind → UInt32
  | .keyword => 0xbb9af7
  | .symbol => 0x89ddff
  | .constant => 0x7aa2f7
  | .ident => plainRgb
  | .number => 0xff9e64
  | .string => 0x9ece6a
  | .comment => 0x565f89
  | .error => 0xf7768e

-- A stretch of a row in one colour, from column `col`. A row is a list
-- of them, each drawn as one `mono`.
structure Run where
  col : Nat
  rgb : UInt32
  text : String

abbrev Row := List Run

-- Characters coloured one by one, in rows of `cols`: each row's runs of
-- one colour. A space goes in the run before it, whatever its colour (it
-- draws nothing), so a row has as few runs as it can. No characters is
-- one empty row.
def runRows (cols : Nat) (cs : Array Char) (rgbs : Array UInt32) : List Row :=
  (List.range (max 1 ((cs.size + cols - 1) / cols))).map fun i =>
    let lo := i * cols
    let runs := (List.range' lo (min cs.size (lo + cols) - lo)).foldl (init := ([] : List Run))
      fun runs j =>
        let c := cs[j]!
        let rgb := rgbs[j]!
        match runs with
        | run :: rest =>
          if c == ' ' || run.rgb == rgb then { run with text := run.text.push c } :: rest
          else { col := j - lo, rgb, text := c.toString } :: runs
        | [] => if c == ' ' then [] else [{ col := j - lo, rgb, text := c.toString }]
    runs.reverse

-- `s`, which may span lines, in rows of `cols`, all in `rgb`.
def lines (s : String) (rgb : UInt32) (cols : Nat) : List Row :=
  (s.splitOn "\n").flatMap fun l =>
    let cs := l.toList.toArray
    runRows cols cs (Array.replicate cs.size rgb)

-- The colour of each of `n` characters: its token's, or plain.
def tokenColours (n : Nat) (tokens : Array Token) : Array UInt32 :=
  tokens.foldl (init := Array.replicate n plainRgb) fun a t =>
    (List.range' t.start (min t.stop n - t.start)).foldl (fun a i => a.set! i t.kind.rgb) a

-- The prompt, then a line coloured by its tokens, in rows of `cols`.
def promptRows (cols : Nat) (s : String) (tokens : Array Token) : List Row :=
  let cs := s.toList.toArray
  runRows cols (prompt.toList.toArray ++ cs)
    (Array.replicate prompt.length promptRgb ++ tokenColours cs.size tokens)

def Entry.rows (cols : Nat) : Entry → List Row
  | .input s tokens => promptRows cols s tokens
  | .output s => lines s 0x9ece6a cols
  | .note s => lines s 0x565f89 cols
  | .warning s => lines s 0xe0af68 cols
  | .error s => lines s 0xf7768e cols

-- What Tab offered, without the namespace typed before them (`map`,
-- not `List.map`), in at most `most` rows; if they don't fit, the last
-- row says how many more. As many columns as the names shown fit in,
-- each as wide as the longest of them.
def Offer.rows (o : Offer) (cols : Nat) (most : Nat := 6) : List Row :=
  if o.names.isEmpty then lines s!"nothing here starts with {o.word}" 0x565f89 cols else
  let typed := (o.word.toList.reverse.dropWhile (· != '.')).length
  let names := o.names.map fun n => String.ofList (n.toList.drop typed)
  let width (per : Nat) : Nat :=
    ((names.take (per * most)).foldl (fun m n => max m n.length) 0) + 2
  let per := ((List.range (cols / 3)).reverse.find? fun i => (i + 1) * width (i + 1) ≤ cols + 2)
    |>.map (· + 1) |>.getD 1
  let w := width per
  let rows := (names.length + per - 1) / per
  let shown := if rows ≤ most then rows else most - 1
  let row (i : Nat) : Row :=
    ((names.drop (i * per)).take per).zipIdx.map fun (n, k) =>
      { col := k * w, rgb := 0x9aa5ce, text := n }
  (List.range shown).map row ++
    (if rows ≤ most then []
     else lines s!"… and {o.names.length - shown * per} more: type more of the name" 0x565f89 cols)

-- The transcript, then a row that says a run is going, then the line
-- being edited and the cursor in it, then what Tab offered. Long lines
-- wrap. When it all doesn't fit, the oldest rows go off the top, so the
-- newest stay in view.
def Repl.view (r : Repl) (w h : Float) : Picture :=
  let adv := monoAdvance replFont
  let cols := max 4 ((w - 2 * replPad) / adv).floor.toUInt64.toNat
  let fits := max 1 ((h - 2 * replPad) / replLineH).floor.toUInt64.toNat
  -- Where the cursor is, counting the prompt. At the end of a full row
  -- it starts the next one.
  let p := prompt.length + r.line.cursor
  let editing := promptRows cols r.line.text r.tokens
  let editing := if p / cols < editing.length then editing else editing ++ [[]]
  let status : List Row := match r.waiting with
    | some w => lines (if w.stopping then "stopping…" else "running… Ctrl+C stops it")
        0xe0af68 cols
    | none => []
  let offered := match r.offer with
    | some o => o.rows cols
    | none => []
  -- Only the newest entries are cut into rows: enough to fill the view.
  let rec newest (es : List Entry) (rows : List Row) (n : Nat) : List Row :=
    match es with
    | e :: rest =>
      if n ≥ fits then rows
      else
        let rs := e.rows cols
        newest rest (rs ++ rows) (n + rs.length)
    | [] => rows
  let below := status ++ editing ++ offered
  let all := newest r.transcript below below.length
  let gone := all.length - fits
  let rows := all.drop gone
  let cursorRow := all.length - offered.length - editing.length + p / cols - gone
  let top (i : Nat) : Float := replPad + replLineH * i.toFloat
  .group (rows.zipIdx.flatMap (fun (row, i) =>
      row.map fun run =>
        .mono (replPad + adv * run.col.toFloat) (top i + 14) replFont run.rgb run.text) ++
    [.rect (replPad + adv * (p % cols).toFloat - 1) (top cursorRow + 2)
       2 (replLineH - 4) 0 0xbb9af7])

def repl : App :=
  App.asking "REPL"
    ({ transcript := [.note "Lean, with Init and the desktop's modules, LeanMachine \
         open. A line is commands, or a term to evaluate. `world` is the desktop \
         when you press Enter; `launch app` opens an app. Ctrl+C stops a run. \
         Up, Down: history. Tab completes a name."] } : Repl)
    Repl.step Repl.view (size := (560, 300))

end LeanMachine
