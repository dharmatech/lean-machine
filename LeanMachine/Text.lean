import LeanMachine.App

/-! # Text: editing a line, colouring tokens, and what Tab offers

What the REPL and the editor share. A line being edited is a pair of
lists around the cursor. Text is monospace, so a row of characters,
each with its colour, is drawn as runs of one colour, a `mono` each, at
the column the run starts in. Pure. -/

namespace LeanMachine

/-! ## A line being edited -/

-- The characters before the cursor, nearest first, and those after it.
-- Every edit takes or adds a character at the head of one of them.
structure Line where
  before : List Char := []
  after : List Char := []
  deriving Inhabited

namespace Line

-- `s`, with the cursor at its end.
def ofString (s : String) : Line := { before := s.toList.reverse }

-- `s`, with the cursor after its first `col` characters (or at its end).
def «at» (s : String) (col : Nat) : Line :=
  let cs := s.toList
  { before := (cs.take col).reverse, after := cs.drop col }

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

/-! ### Several lines in one

The REPL's line may hold several, with "\n" between them; the editor's
never does, so these are the same as the moves above there. -/

-- The cursor's column in its own line: the characters back to a "\n".
def column (l : Line) : Nat := (l.before.takeWhile (· != '\n')).length

-- The start and end of the cursor's own line: Home and End.
def lineStart (l : Line) : Line :=
  let (cs, rest) := l.before.span (· != '\n')
  { before := rest, after := cs.reverse ++ l.after }

def lineEnd (l : Line) : Line :=
  let (cs, rest) := l.after.span (· != '\n')
  { before := cs.reverse ++ l.before, after := rest }

-- Right `n` characters, but not past the end of the cursor's line.
def forward (l : Line) : Nat → Line
  | 0 => l
  | n + 1 =>
    match l.after with
    | c :: cs => if c == '\n' then l else forward { before := c :: l.before, after := cs } n
    | [] => l

-- To the line above or below, at the same column or that line's end;
-- `none` from the first line, or the last.
def up (l : Line) : Option Line :=
  match l.lineStart.before with
  | '\n' :: rest => some ((Line.lineStart { before := rest, after := [] }).forward l.column
      |> fun to => { to with after := to.after ++ '\n' :: l.lineStart.after })
  | _ => none

def down (l : Line) : Option Line :=
  match l.lineEnd.after with
  | '\n' :: rest => some (forward { before := '\n' :: l.lineEnd.before, after := rest } l.column)
  | _ => none

-- The cursor's own line: its characters.
def own (l : Line) : List Char :=
  (l.before.takeWhile (· != '\n')).reverse ++ l.after.takeWhile (· != '\n')

end Line

#guard (Line.at "ab\ncdef\ng" 5).column == 2
#guard ((Line.at "ab\ncdef\ng" 5).up.map (·.cursor)) == some 2
#guard ((Line.at "abcd\nef" 7).up.map fun l => (l.cursor, l.text)) == some (2, "abcd\nef")
#guard ((Line.at "ab\ncdef" 1).down.map (·.cursor)) == some 4
#guard ((Line.at "ab\ncdef" 4).down.map (·.cursor)) == none
#guard (Line.at "ab\ncdef\ng" 5).lineStart.cursor == 3
#guard (Line.at "ab\ncdef\ng" 5).lineEnd.cursor == 7
#guard String.ofList (Line.at "ab\ncdef\ng" 5).own == "cdef"

-- How far in a new line starts when Enter cuts `line` (its characters)
-- after `col` of them: as far in as it starts, or the cut if that's
-- sooner, and two more after `:=`, `do`, `where`, `=>`, `by`, `then` or
-- `else`.
def indentAfter (line : List Char) (col : Nat) : Nat :=
  let before := String.ofList (line.take col)
  let opens := [":=", " do", "where", "=>", " by", "then", "else"].any
    (before.trimAsciiEnd.toString.endsWith ·)
  min col (line.takeWhile (· == ' ')).length + if opens then 2 else 0

#guard indentAfter "  def x :=".toList 10 == 4
#guard indentAfter "    2 * n".toList 9 == 4
#guard indentAfter "    2 * n".toList 2 == 2

/-! ## Pasted text -/

-- Pasted text as lines: ended by "\n", "\r\n" or "\r"; each tab two
-- spaces, as Lean takes no tabs; other control characters dropped.
-- Text that ends a line gives an empty last line.
def pastedLines (s : String) : List String :=
  let tidy (l : String) : String :=
    l.toList.foldl (init := "") fun t c =>
      if c == '\t' then t ++ "  " else if c.toNat < 32 || c.toNat == 127 then t else t.push c
  (((s.replace "\r\n" "\n").replace "\r" "\n").splitOn "\n").map tidy

#guard pastedLines "def x := 1" == ["def x := 1"]
#guard pastedLines "a\r\n\tb\rc\n" == ["a", "  b", "c", ""]
#guard pastedLines "a\x00b\x1b[0m" == ["ab[0m"]

/-! ## Colours and rows -/

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

-- Is column `at_` inside a string, a comment, or where the tokenizer
-- gave up, as `tokens` say? Tab doesn't complete there.
def inText (tokens : Array Token) (at_ : Nat) : Bool :=
  tokens.any fun t =>
    t.start < at_ && at_ ≤ t.stop && [.string, .comment, .error].contains t.kind

/-! ## What Tab offers -/

-- What Tab found for the name before the cursor: what it could become
-- (none: nothing here starts with it).
structure Offer where
  word : String
  names : List String

-- The name before the cursor, as far back as there are characters a
-- name can have, dots included: `Nat.su` in `(Nat.su`. Empty unless it
-- starts the way a name does (not `.1`, `3.5` or `x.`'s field).
def wordBefore (before : List Char) : String :=
  match (before.takeWhile fun c => Lean.isIdRest c || c == '.').reverse with
  | c :: cs => if Lean.isIdFirst c then String.ofList (c :: cs) else ""
  | [] => ""

def commonPrefix : List String → String
  | [] => ""
  | s :: rest => rest.foldl (init := s) fun a b =>
      String.ofList (((a.toList.zip b.toList).takeWhile fun (x, y) => x == y).map (·.1))

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

end LeanMachine
