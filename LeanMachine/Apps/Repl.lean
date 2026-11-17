import LeanMachine.App

/-! # REPL: a line editor over a transcript

For now it echoes: Enter adds the line, and an echo of it, to the
transcript, and Up and Down recall earlier lines. Pure, no threads; it
will evaluate Lean once the desktop can run work in the background.
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
  | input (s : String)    -- a line entered, shown after the prompt
  | output (s : String)   -- what came back; it may span lines
  deriving Repr

structure Repl where
  line : Line := {}
  transcript : List Entry := []   -- newest first
  history : List String := []     -- lines entered, newest first
  back : Nat := 0                 -- how far back in the history the line is
  draft : String := ""            -- the line being typed, kept while Up goes back
  deriving Inhabited

namespace Repl

def edit (r : Repl) (f : Line → Line) : Repl := { r with line := f r.line }

-- The line and its echo go to the transcript, and the line to the
-- history, unless it's empty or the same as the last one.
def enter (r : Repl) : Repl :=
  let s := r.line.text
  let echo := if s.isEmpty then [] else [Entry.output s]
  { r with line := {}, back := 0, draft := "",
           transcript := echo ++ .input s :: r.transcript,
           history := if s.isEmpty || r.history.head? == some s then r.history
                      else s :: r.history }

-- The line `n` back in the history; 0 is the line that was being typed.
def goBack (r : Repl) (n : Nat) : Repl :=
  let draft := if r.back == 0 then r.line.text else r.draft
  let text := if n == 0 then draft else r.history.getD (n - 1) ""
  { r with back := n, draft, line := .ofString text }

-- Modifiers don't matter yet: Ctrl+Left is Left.
def step (r : Repl) : AppEvent → Option Repl
  | .text s => some (r.edit (·.insert s))
  | .key k _ =>
    match k with
    | .enter => some r.enter
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

-- The transcript, then the line being edited and the cursor in it. Long
-- lines wrap. When it all doesn't fit, the oldest rows go off the top,
-- so the newest stay in view.
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
  -- Only the newest entries are cut into rows: enough to fill the view.
  let rec newest (es : List Entry) (rows : List Row) (n : Nat) : List Row :=
    match es with
    | e :: rest =>
      if n ≥ fits then rows
      else
        let rs := e.rows cols
        newest rest (rs ++ rows) (n + rs.length)
    | [] => rows
  let all := newest r.transcript editing editing.length
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
  App.of "REPL"
    ({ transcript := [.note "Echoes what you enter, for now. Up, Down: history."] } : Repl)
    Repl.step Repl.view (size := (560, 300))

end LeanMachine
