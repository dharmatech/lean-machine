import LeanMachine.App
import LeanMachine.Busy

/-! # REPL: a line editor over a transcript

Enter asks the loop to run the line, on a thread of its own, and the
outcome goes in the transcript when it comes back. The line can be edited
meanwhile, and Ctrl+C stops the run. Until Lean is linked, a line runs as
busy work (`alloc 100` and the like) or comes back as it went. Up and
Down recall earlier lines. Pure: the REPL only asks. Everything is
monospace, so where a character or the cursor goes is arithmetic on
`monoAdvance`. -/

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
  | input (s : String)    -- a line entered, shown after the prompt
  | output (s : String)   -- what came back; it may span lines
  deriving Repr

-- The run the REPL is waiting for.
structure Waiting where
  tag : Nat
  stopping : Bool := false   -- Ctrl+C asked it to stop
  deriving Inhabited

structure Repl where
  line : Line := {}
  transcript : List Entry := []   -- newest first
  history : List String := []     -- lines entered, newest first
  back : Nat := 0                 -- how far back in the history the line is
  draft : String := ""            -- the line being typed, kept while Up goes back
  waiting : Option Waiting := none
  nextTag : Nat := 0
  deriving Inhabited

-- What a line runs, until Lean is linked: busy work by name, `n` million
-- steps of it, or the line itself, which comes back as it went.
def busyWork (line : String) : Unit → String :=
  match (line.splitOn " ").filter (· != "") with
  | [w, n] =>
    match n.toNat? with
    | some n =>
      if w == "alloc" then fun _ => toString (Busy.alloc n)
      else if w == "poll" then fun _ => toString (Busy.polled n)
      else if w == "spin" then fun _ => toString (Busy.spin n)
      else fun _ => line
    | none => fun _ => line
  | _ => fun _ => line

namespace Repl

def edit (r : Repl) (f : Line → Line) : Repl := { r with line := f r.line }

-- The line goes to the transcript and to the history, unless it's empty
-- or the same as the last one, and the REPL asks for it to be run. While
-- a run is going, Enter does nothing.
def enter (r : Repl) : Option (Repl × List Request) :=
  if r.waiting.isSome then none else
  let s := r.line.text
  let r := { r with line := {}, back := 0, draft := "",
                    transcript := .input s :: r.transcript,
                    history := if s.isEmpty || r.history.head? == some s then r.history
                               else s :: r.history }
  if s.isEmpty then some (r, [])
  else some ({ r with waiting := some { tag := r.nextTag }, nextTag := r.nextTag + 1 },
             [.run r.nextTag (busyWork s)])

-- Ctrl+C: stops the run, or with none going, clears the line.
def interrupt (r : Repl) : Option (Repl × List Request) :=
  match r.waiting with
  | some w => some ({ r with waiting := some { w with stopping := true } }, [.stop w.tag])
  | none => some ({ r with line := {}, back := 0, draft := "" }, [])

def took (ms : Nat) : String :=
  if ms < 1000 then s!"{ms} ms"
  else s!"{ms / 1000}.{(ms % 1000) / 100} s"

-- The outcome of the run the REPL is waiting for goes in the transcript.
-- Outcomes of other runs (from before an undo, say) don't matter to it.
def ended (r : Repl) (tag : Nat) (o : Outcome) (ms : Nat) : Option Repl :=
  match r.waiting with
  | some w =>
    if w.tag != tag then none else
    -- In the order they're read.
    let entries : List Entry := match o with
      | .value s =>
        .output s ::
        (if w.stopping then [.note "it didn't stop: nothing on its way was a safepoint"]
         else []) ++
        (if ms ≥ 100 then [.note s!"took {took ms}"] else [])
      | .stopped => [.note (if ms == 0 then "stopped" else s!"stopped after {took ms}")]
      | .failed why => [.note s!"failed: {why}"]
    some { r with waiting := none, transcript := entries.reverse ++ r.transcript }
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

-- Other modifiers don't matter yet: Ctrl+Left is Left.
def step (r : Repl) : AppEvent → Option (Repl × List Request)
  | .text s => some (r.edit (·.insert s), [])
  | .key .enter _ => r.enter
  | .key (.char 'c') m => if m == { ctrl := true } then r.interrupt else none
  | .key k _ => (r.editKey k).map (·, [])
  | .done tag o ms => (r.ended tag o ms).map (·, [])
  | _ => none

end Repl

/-! ## How it looks -/

def replFont : Float := 15     -- monoAdvance 15 = 9 pixels a column
def replLineH : Float := 20
def replPad : Float := 10
def prompt : String := "> "

-- A row on the screen: `lead` in the prompt's color, then `text`.
structure Row where
  lead : String := ""
  text : String
  rgb : UInt32

-- `cs` cut into rows of `cols` characters. No characters is one empty row.
def cut (cols : Nat) (cs : List Char) : List (List Char) :=
  let a := cs.toArray
  (List.range (max 1 ((a.size + cols - 1) / cols))).map fun i =>
    (a.extract (i * cols) ((i + 1) * cols)).toList

-- The prompt and the characters after it, in rows of `cols`.
def promptRows (cols : Nat) (cs : List Char) : List Row :=
  (cut cols (prompt.toList ++ cs)).zipIdx.map fun (row, i) =>
    if i == 0 then
      { lead := String.ofList (row.take prompt.length),
        text := String.ofList (row.drop prompt.length), rgb := 0xc0caf5 }
    else { text := String.ofList row, rgb := 0xc0caf5 }

def Entry.rows (cols : Nat) : Entry → List Row
  | .input s => promptRows cols s.toList
  | .output s => ((s.toList.splitOn '\n').flatMap (cut cols)).map fun row =>
      { text := String.ofList row, rgb := 0x9ece6a }
  | .note s => (cut cols s.toList).map fun row =>
      { text := String.ofList row, rgb := 0x565f89 }

-- The transcript, then a row that says a run is going, then the line
-- being edited and the cursor in it. Long lines wrap. When it all doesn't
-- fit, the oldest rows go off the top, so the newest stay in view.
def Repl.view (r : Repl) (w h : Float) : Picture :=
  let adv := monoAdvance replFont
  let cols := max 4 ((w - 2 * replPad) / adv).floor.toUInt64.toNat
  let fits := max 1 ((h - 2 * replPad) / replLineH).floor.toUInt64.toNat
  -- Where the cursor is, counting the prompt. At the end of a full row
  -- it starts the next one.
  let p := prompt.length + r.line.cursor
  let editing := promptRows cols r.line.chars
  let editing :=
    if p / cols < editing.length then editing
    else editing ++ [{ text := "", rgb := 0 }]
  let status : List Row := match r.waiting with
    | some w => (cut cols (if w.stopping then "stopping…".toList
                           else "running… Ctrl+C stops it".toList)).map fun row =>
        { text := String.ofList row, rgb := 0xe0af68 }
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
  let all := newest r.transcript (status ++ editing) (status.length + editing.length)
  let gone := all.length - fits
  let rows := all.drop gone
  let cursorRow := all.length - editing.length + p / cols - gone
  let top (i : Nat) : Float := replPad + replLineH * i.toFloat
  .group (rows.zipIdx.flatMap (fun (row, i) =>
      let y := top i + 14
      (if row.lead.isEmpty then [] else [.mono replPad y replFont 0x7aa2f7 row.lead]) ++
      [.mono (replPad + adv * row.lead.length.toFloat) y replFont row.rgb row.text]) ++
    [.rect (replPad + adv * (p % cols).toFloat - 1) (top cursorRow + 2)
       2 (replLineH - 4) 0 0xbb9af7])

def repl : App :=
  App.asking "REPL"
    ({ transcript := [.note "No Lean yet. Enter runs a line on a thread of its own. \
         Busy work, seconds of it: alloc 100, poll 1000, spin 1000 (millions of \
         steps). Anything else comes back as it went. Ctrl+C stops a run. \
         Up, Down: history."] } : Repl)
    Repl.step Repl.view (size := (560, 300))

end LeanMachine
