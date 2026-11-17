import LeanMachine.Text

/-! # Editor: a Lean file, coloured and completed by the desktop's Lean

It opens on a list of the desktop's own Lean files: type to narrow it,
Up and Down to choose, Enter (or a click) to open one. The file is a
list of lines around the cursor's: every edit changes the cursor's line,
and a move takes a line from one list to the other. Each line keeps its
tokens and where the next line starts (in code, a comment or a string),
so a comment that spans lines is coloured as one, and an edit reads
again only its own line and the lines below that start differently now.
Ctrl+S saves and Ctrl+O goes back to the list.

Pure, like the REPL: reading, saving and listing files are requests,
and so is the desktop's Lean, which colours the file and completes names
(Tab). -/

namespace LeanMachine

/-! ## The file -/

-- A line of the file, with its tokens and where it and the next line
-- start, as the editor's Lean read them (all `code` and no tokens
-- until the editor has its Lean).
structure Lexed where
  text : String
  tokens : Array Token := #[]
  carryIn : Carry := .code
  carry : Carry := .code
  deriving Inhabited

-- The file: the lines above the cursor's, nearest first, the cursor's
-- line being edited, with its tokens, and the lines below, nearest first.
structure Buffer where
  above : List Lexed := []
  line : Line := {}
  here : Lexed := { text := "" }   -- the cursor's line as last read
  below : List Lexed := []
  row : Nat := 0                   -- the cursor's line, from 0
  deriving Inhabited

namespace Buffer

-- A file's text, the cursor at its start. Line ends may be "\r\n".
def ofText (s : String) : Buffer :=
  let rows := (s.splitOn "\n").map fun l =>
    if l.endsWith "\r" then (l.dropEnd 1).toString else l
  match rows with
  | first :: rest => { line := .at first 0, here := { text := first },
                       below := rest.map ({ text := · }) }
  | [] => {}

def col (b : Buffer) : Nat := b.line.cursor
def count (b : Buffer) : Nat := b.above.length + 1 + b.below.length

-- The cursor's line, as a line of the file.
def current (b : Buffer) : Lexed := { b.here with text := b.line.text }

def lines (b : Buffer) : List String :=
  (b.above.reverse.map (·.text)) ++ b.line.text :: b.below.map (·.text)

-- The file's text, lines ended with "\n" but the last.
def text (b : Buffer) : String := "\n".intercalate b.lines

-- Where the cursor's line starts.
def carryIn (b : Buffer) : Carry := (b.above.head?.map (·.carry)).getD .code

-- To the line above, at column `col` or its end.
def up (b : Buffer) (col : Nat) : Buffer :=
  match b.above with
  | l :: rest => { above := rest, line := .at l.text col, here := l,
                   below := b.current :: b.below, row := b.row - 1 }
  | [] => b

def down (b : Buffer) (col : Nat) : Buffer :=
  match b.below with
  | l :: rest => { above := b.current :: b.above, line := .at l.text col, here := l,
                   below := rest, row := b.row + 1 }
  | [] => b

-- To line `row` (or the last), column `col`, a line at a time.
partial def goTo (b : Buffer) (row col : Nat) : Buffer :=
  if row < b.row && !b.above.isEmpty then (b.up col).goTo row col
  else if row > b.row && !b.below.isEmpty then (b.down col).goTo row col
  else { b with line := .at b.line.text col }

-- Enter: the line is cut at the cursor, and the new line starts as far
-- in as the line did, and two more after `:=`, `do`, `where`, `=>`,
-- `by`, `then` or `else`.
def enter (b : Buffer) : Buffer :=
  let before := String.ofList b.line.before.reverse
  let indent := min b.line.cursor (b.line.chars.takeWhile (· == ' ')).length
  let opens := [":=", " do", "where", "=>", " by", "then", "else"].any
    (before.trimAsciiEnd.toString.endsWith ·)
  let pad := String.ofList (List.replicate (indent + if opens then 2 else 0) ' ')
  { b with above := { b.here with text := before } :: b.above,
           line := { before := pad.toList.reverse, after := b.line.after },
           row := b.row + 1 }

-- Backspace at the start of a line joins it to the line above.
def backspace (b : Buffer) : Buffer :=
  if b.col > 0 then { b with line := b.line.backspace } else
  match b.above with
  | l :: rest => { b with above := rest, here := l, row := b.row - 1,
                          line := { before := l.text.toList.reverse, after := b.line.chars } }
  | [] => b

-- Delete at the end of a line joins the line below to it.
def delete (b : Buffer) : Buffer :=
  if !b.line.after.isEmpty then { b with line := b.line.delete } else
  match b.below with
  | l :: rest => { b with below := rest, line := { b.line with after := l.text.toList } }
  | [] => b

-- Left at the start of a line goes to the end of the line above; Right
-- at the end, to the start of the line below.
def left (b : Buffer) : Buffer :=
  if b.col > 0 then { b with line := b.line.left }
  else match b.above.head? with
    | some l => b.up l.text.length
    | none => b

def right (b : Buffer) : Buffer :=
  if !b.line.after.isEmpty then { b with line := b.line.right }
  else if b.below.isEmpty then b else b.down 0

/-! ### Reading the lines -/

def lexed (env : Env) (c : Carry) (text : String) : Lexed :=
  let (tokens, carry) := env.tokensFrom c text
  { text, tokens, carryIn := c, carry }

-- The lines below, read again from where the line above them now ends,
-- as far as a line starts where it did.
def again (env : Env) : Carry → List Lexed → List Lexed
  | _, [] => []
  | c, l :: rest =>
    if l.carryIn == c then l :: rest
    else
      let l := lexed env c l.text
      l :: again env l.carry rest

-- After the cursor's line changed: it's read again, and the lines below
-- as far as they start differently now.
def relex (env : Env) (b : Buffer) : Buffer :=
  let here := lexed env b.carryIn b.line.text
  { b with here, below := again env here.carry b.below }

-- After Enter: the line above, which the cursor left, and the rest.
def relexAbove (env : Env) (b : Buffer) : Buffer :=
  match b.above with
  | l :: rest =>
    let c := (rest.head?.map (·.carry)).getD .code
    relex env { b with above := lexed env c l.text :: rest }
  | [] => relex env b

-- Every line, from the top: once the editor has its Lean, or a file.
def lexAll (env : Env) (b : Buffer) : Buffer :=
  let (above, c) := b.above.reverse.foldl (init := ([], Carry.code)) fun (ls, c) l =>
    let l := lexed env c l.text
    (l :: ls, l.carry)
  let here := lexed env c b.line.text
  let (below, _) := b.below.foldl (init := ([], here.carry)) fun (ls, c) l =>
    let l := lexed env c l.text
    (l :: ls, l.carry)
  { b with above, here, below := below.reverse }

end Buffer

/-! ## The editor -/

def editorSize : Float × Float := (760, 520)
def edFont : Float := 14        -- monoAdvance 14 = 8.4 pixels a column
def edLineH : Float := 19
def edPad : Float := 8
def edStatusH : Float := 24
def gutterCols : Nat := 5       -- line numbers up to 9999, and a space

-- How many lines and columns of the file the editor shows. Windows don't
-- change size yet, so it's the size the editor asks for.
def edRows : Nat := ((editorSize.2 - 2 * edPad - edStatusH) / edLineH).floor.toUInt64.toNat
def edCols : Nat :=
  ((editorSize.1 - 2 * edPad) / monoAdvance edFont).floor.toUInt64.toNat - gutterCols

-- The runs the editor waits for, by tag. Each kind has a tag of its
-- own, so a new request replaces only one of its own kind.
def edLeanTag : Nat := 0
def listTag : Nat := 1
def readTag : Nat := 2
def writeTag : Nat := 3

structure Editor where
  path : Option String := none   -- the file open; `none`: choosing one
  files : Array String := #[]    -- the Lean files to choose from
  filter : Line := {}            -- what's typed to narrow them
  pick : Nat := 0                -- the one chosen, among those shown
  opening : Option String := none
  buffer : Buffer := {}
  goal : Option Nat := none      -- the column Up and Down keep to
  top : Nat := 0                 -- the first line in view
  left : Nat := 0                -- the first column in view
  wheelRest : Float := 0         -- a wheel's turn too small to scroll yet
  env : Option Env := none       -- the desktop's Lean, once it comes
  asked : Option TimeOfDay := none  -- the tick it last asked for what it lacks in
  offer : Option Offer := none
  edits : Nat := 0               -- edits since the file was opened
  savedAt : Nat := 0             -- `edits` when it was last read or saved
  savingAt : Option Nat := none
  leaving : Bool := false        -- Ctrl+O pressed once with changes not saved
  note : String := ""            -- what the status line says last

namespace Editor

def changed (e : Editor) : Bool := e.edits != e.savedAt

-- The files shown: those whose path has what's typed in it, any case.
def shown (e : Editor) : Array String :=
  let f := e.filter.text.toLower
  e.files.filter fun p => (p.toLower.splitOn f).length > 1 || f.isEmpty

def fileName (p : String) : String := (p.splitOn "/").getLastD p

def title (e : Editor) : String :=
  match e.path with
  | some p => fileName p ++ (if e.changed then " •" else "")
  | none => "Editor"

-- It asks for what it lacks: the desktop's Lean, and the files to choose
-- from. At most once a second, as an undo may bring back an editor
-- whose answers went to a world that's gone.
def ask (e : Editor) (t : TimeOfDay) : Option (Editor × List Request) :=
  let asks := (if e.env.isNone then [Request.eval edLeanTag "" none] else []) ++
    (if e.path.isNone && e.files.isEmpty then [.list listTag "."] else [])
  if asks.isEmpty || e.asked == some t then none
  else some ({ e with asked := some t }, asks)

-- An edit of the file: the line is read again, Up and Down forget their
-- column, and the offer goes.
def edit (e : Editor) (f : Buffer → Buffer) (relex : Env → Buffer → Buffer := Buffer.relex) :
    Editor :=
  let b := f e.buffer
  { e with buffer := (e.env.map (relex · b)).getD b, edits := e.edits + 1, goal := none,
           offer := none, note := "" }

-- A move: the cursor goes elsewhere, the file stays.
def move (e : Editor) (f : Buffer → Buffer) : Editor :=
  { e with buffer := f e.buffer, goal := none, offer := none }

-- Up and Down keep to the column they started from.
def vertical (e : Editor) (to : Buffer → Nat → Buffer) : Editor :=
  let goal := e.goal.getD e.buffer.col
  { e with buffer := to e.buffer goal, goal := some goal, offer := none }

def opened (e : Editor) (path text : String) (ms : Nat) : Editor :=
  let b := Buffer.ofText text
  { e with path := some path, opening := none, buffer := (e.env.map (Buffer.lexAll · b)).getD b,
           edits := 0, savedAt := 0, top := 0, left := 0, goal := none, offer := none,
           note := s!"read {b.count} lines in {ms} ms" }

-- Back to the list of files, which is asked for again.
def toFiles (e : Editor) : Editor × List Request :=
  ({ e with path := none, buffer := {}, filter := {}, pick := 0, note := "", leaving := false },
   [.list listTag "."])

def save (e : Editor) : Option (Editor × List Request) := do
  let path ← e.path
  if e.savingAt.isSome then none
  some ({ e with savingAt := some e.edits, note := "saving…" }, [.write writeTag path e.buffer.text])

-- Tab: the name before the cursor, finished as far as every name it
-- could become agrees, from the editor's Lean; with no name there, or in
-- a string or a comment, spaces to the next even column.
def tab (e : Editor) : Editor :=
  let b := e.buffer
  let word := wordBefore b.line.before
  match e.env with
  | some env =>
    if !word.isEmpty && !inText b.here.tokens b.col then
      let names := (env.complete word).toList
      let more := String.ofList ((commonPrefix names).toList.drop word.length)
      let e := if more.isEmpty then e else e.edit (fun b => { b with line := b.line.insert more })
      { e with offer := if names.length == 1 then none else some { word, names } }
    else e.edit fun b => { b with line := b.line.insert (if b.col % 2 == 0 then "  " else " ") }
  | none => e.edit fun b => { b with line := b.line.insert (if b.col % 2 == 0 then "  " else " ") }

-- Keys while a file is open.
def editKey (e : Editor) (k : Key) (m : Mods) : Option (Editor × List Request) :=
  let e' := { e with leaving := false }
  if m.ctrl then
    match k with
    | .char 's' => e'.save
    | .char 'o' =>
      if e.changed && !e.leaving then
        some ({ e with leaving := true, note := "not saved: Ctrl+O again leaves the changes" }, [])
      else some e.toFiles
    | .home => some (e'.move (·.goTo 0 0), [])
    | .«end» => some (e'.move fun b => b.goTo (b.count - 1) 0 |> fun b => { b with line := b.line.toEnd }, [])
    | _ => none
  else
    let page := edRows - 1
    let e := e'
    match k with
    | .enter => some (e.edit Buffer.enter Buffer.relexAbove, [])
    | .backspace => some (e.edit Buffer.backspace, [])
    | .delete => some (e.edit Buffer.delete, [])
    | .tab => some (e.tab, [])
    | .left => some (e.move Buffer.left, [])
    | .right => some (e.move Buffer.right, [])
    | .home => some (e.move fun b => { b with line := b.line.toStart }, [])
    | .«end» => some (e.move fun b => { b with line := b.line.toEnd }, [])
    | .up => some (e.vertical Buffer.up, [])
    | .down => some (e.vertical Buffer.down, [])
    | .pageUp => some (e.vertical fun b c => b.goTo (b.row - page) c, [])
    | .pageDown => some (e.vertical fun b c => b.goTo (b.row + page) c, [])
    | _ => none

-- Keys while choosing a file.
def chooseKey (e : Editor) (k : Key) : Option (Editor × List Request) :=
  let n := e.shown.size
  match k with
  | .up => if e.pick > 0 then some ({ e with pick := e.pick - 1 }, []) else none
  | .down => if e.pick + 1 < n then some ({ e with pick := e.pick + 1 }, []) else none
  | .backspace => some ({ e with filter := e.filter.backspace, pick := 0 }, [])
  | .delete => some ({ e with filter := e.filter.delete, pick := 0 }, [])
  | .left => some ({ e with filter := e.filter.left }, [])
  | .right => some ({ e with filter := e.filter.right }, [])
  | .enter => do
    let path ← e.shown[e.pick]?
    some ({ e with opening := some path, note := s!"reading {path}…" }, [.read readTag path])
  | _ => none

-- The first line in view, and the first column, after the cursor moved:
-- as they were if the cursor is still in view, or as little changed as
-- brings it in.
def follow (e : Editor) : Editor :=
  let row := e.buffer.row
  let col := e.buffer.col
  let top := if row < e.top then row else if row ≥ e.top + edRows then row + 1 - edRows else e.top
  let left := if col < e.left then col - min col 8
    else if col ≥ e.left + edCols then col + 9 - edCols else e.left
  { e with top, left }

-- Where a press lands: the line and column of the file, or the file shown.
def listTopFor (pick : Nat) : Nat := if pick < edRows - 2 then 0 else pick + 3 - edRows

def textX : Float := edPad + gutterCols.toFloat * monoAdvance edFont

def pressed (e : Editor) (x y : Float) : Option (Editor × List Request) :=
  let row := ((y - edPad) / edLineH).floor
  if row < 0 then none else
  let row := row.toUInt64.toNat
  match e.path with
  | some _ =>
    if row ≥ edRows then none else
    let col := ((x - textX) / monoAdvance edFont).round
    let col := if col < 0 then 0 else col.toUInt64.toNat
    some (e.move (·.goTo (e.top + row) (e.left + col)), [])
  | none =>
    -- Rows 0 and 1 are the heading and what's typed.
    if row < 2 then none else
    let pick := listTopFor e.pick + row - 2
    if pick < e.shown.size then
      { e with pick }.chooseKey .enter
    else none

-- The wheel scrolls the file three lines a step and leaves the cursor
-- where it is; a touchpad's fractions add up.
def wheel (e : Editor) (dy : Float) : Option (Editor × List Request) := do
  let _ ← e.path
  let total := e.wheelRest + 3 * dy
  let lines := if total ≥ 0 then total.floor else total.ceil
  let rest := total - lines
  let top := if lines ≥ 0 then e.top - min e.top lines.toUInt64.toNat
    else min (e.buffer.count - 1) (e.top + (-lines).toUInt64.toNat)
  some ({ e with top, wheelRest := rest }, [])

-- A run the editor asked for ended.
def ended (e : Editor) (tag : Nat) (o : Outcome) (ms : Nat) : Option Editor :=
  -- Tags: the editor's Lean 0, the files 1, reading 2, saving 3.
  match tag, o with
  | 0, .evaluated _ env =>
    if e.env.isSome then none
    else some { e with env := some env, buffer := Buffer.lexAll env e.buffer }
  | 1, .listed paths =>
    some { e with files := (paths.filter (·.endsWith ".lean")).toArray, pick := 0 }
  | 2, .read text => do
    let path ← e.opening
    some (e.opened path text ms)
  | 2, .failed why => some { e with opening := none, note := s!"can't read it: {why}" }
  | 3, .wrote => do
    let at_ ← e.savingAt
    some { e with savedAt := at_, savingAt := none, note := s!"saved" }
  | 3, .failed why => some { e with savingAt := none, note := s!"can't save it: {why}" }
  | 1, .failed why => some { e with note := s!"can't list the files: {why}" }
  | _, _ => none

def heard (e : Editor) : AppEvent → Option (Editor × List Request)
  | .tick t => e.ask t
  | .done tag o ms => (e.ended tag o ms).map (·, [])
  | .wheel _ _ dy => e.wheel dy
  | .press x y => (e.pressed x y).map fun (e, asks) => (e.follow, asks)
  | .text s =>
    match e.path with
    | some _ => some ((e.edit fun b => { b with line := b.line.insert s }).follow, [])
    | none => some ({ e with filter := e.filter.insert s, pick := 0 }, [])
  | .key k m =>
    match e.path with
    | some _ => (e.editKey k m).map fun (e, asks) => (if e.path.isSome then e.follow else e, asks)
    | none => if m.ctrl then none else e.chooseKey k
  | _ => none

end Editor

/-! ## How it looks -/

def gutterRgb : UInt32 := 0x3b4261
def hereRgb : UInt32 := 0x1f2335    -- behind the cursor's line
def statusRgb : UInt32 := 0x16161e

-- A line of the file from column `left`, `cols` of it, coloured by its
-- tokens, as one row of runs.
def lexedRow (l : Lexed) (left cols : Nat) : Row :=
  let cs := l.text.toList.toArray
  let rgbs := tokenColours cs.size l.tokens
  let hi := min cs.size (left + cols)
  let lo := min left hi
  ((runRows cols (cs.extract lo hi) (rgbs.extract lo hi)).head?).getD []

def drawRow (x y : Float) (row : Row) : List Picture :=
  row.map fun run => .mono (x + monoAdvance edFont * run.col.toFloat) y edFont run.rgb run.text

-- `n`, right-aligned in `width` columns.
def rightAligned (n width : Nat) : String :=
  let s := toString n
  String.ofList (List.replicate (width - s.length) ' ') ++ s

namespace Editor

-- The lines in view, with their numbers from 0, top to bottom.
def inView (e : Editor) : List (Nat × Lexed) :=
  let b := e.buffer
  let bottom := e.top + edRows
  let aboveTo := min bottom b.row          -- lines from `top` up to there are above
  let aboveShown := if e.top < aboveTo
    then ((b.above.drop (b.row - aboveTo)).take (aboveTo - e.top)).reverse else []
  let here := if e.top ≤ b.row && b.row < bottom then [b.current] else []
  let belowFrom := max e.top (b.row + 1)
  let belowShown := if belowFrom < bottom
    then (b.below.drop (belowFrom - b.row - 1)).take (bottom - belowFrom) else []
  -- Whichever of them are there, the first is line `top`.
  (aboveShown ++ here ++ belowShown).zipIdx.map fun (l, i) => (e.top + i, l)

-- The top of row `i` of the view.
def rowY (i : Nat) : Float := edPad + edLineH * i.toFloat

def viewFile (e : Editor) (w h : Float) : List Picture :=
  let adv := monoAdvance edFont
  let b := e.buffer
  let rows := e.inView
  let lineRows := rows.zipIdx.flatMap fun ((n, l), i) =>
    let y := rowY i + 14
    (if n == b.row then [.rect 0 (rowY i) w edLineH 0 hereRgb] else []) ++
    [.mono edPad y edFont (if n == b.row then 0x737aa2 else gutterRgb)
      (rightAligned (n + 1) (gutterCols - 1))] ++
    drawRow textX y (lexedRow l e.left edCols)
  let cursorAt := if e.top ≤ b.row && b.row < e.top + edRows && e.left ≤ b.col then
      [Picture.rect (textX + adv * (b.col - e.left).toFloat - 1) (rowY (b.row - e.top) + 2) 2
        (edLineH - 4) 0 0xbb9af7]
    else []
  -- What Tab offered, in a box under the cursor's line, or over it near
  -- the bottom.
  let offered : List Picture := match e.offer with
    | some o =>
      let rows := o.rows 60
      let width := rows.foldl (fun m r => r.foldl (fun m run => max m (run.col + run.text.length)) m) 0
      let boxW := adv * width.toFloat + 12
      let boxH := edLineH * rows.length.toFloat + 8
      let r := b.row - e.top
      let y := if r + 1 + rows.length ≤ edRows then rowY (r + 1) else rowY r - boxH
      let x := min (w - boxW - 4) (textX + adv * ((b.col - min b.col (wordBefore b.line.before).length) - e.left).toFloat - 6)
      [.rect x y boxW boxH 4 0x414868, .rect (x + 1) (y + 1) (boxW - 2) (boxH - 2) 4 0x24283b] ++
      rows.zipIdx.flatMap fun (row, i) => drawRow (x + 6) (y + 4 + edLineH * i.toFloat + 14) row
    | none => []
  let path := e.path.getD ""
  let state := if e.savingAt.isSome then "saving…" else if e.changed then "changed" else "saved"
  let status := s!"{path}   {b.row + 1}:{b.col + 1}   {if e.note.isEmpty then state else e.note}"
  lineRows ++ cursorAt ++ offered ++
    [.rect 0 (h - edStatusH) w edStatusH 0 statusRgb,
     .mono edPad (h - 7) 13 (if e.changed then 0xe0af68 else 0x9aa5ce) status,
     .textIn 0 (h - edStatusH) (w - edPad) edStatusH 12 .right 0x565f89
       "Ctrl+S save · Ctrl+O files"]

def viewFiles (e : Editor) (w _h : Float) : List Picture :=
  let adv := monoAdvance edFont
  let shown := e.shown
  let top := listTopFor e.pick
  let rows := (shown.toList.drop top).take (edRows - 2)
  let heading := if e.files.isEmpty then (if e.note.isEmpty then "looking for files…" else e.note)
    else if e.opening.isSome then e.note
    else if e.note.isEmpty then s!"{shown.size} of {e.files.size} Lean files: type to narrow, Up, Down, Enter"
    else e.note
  [.mono edPad (rowY 0 + 14) edFont 0x565f89 heading,
   .mono edPad (rowY 1 + 14) edFont 0x7aa2f7 ("> " ++ e.filter.text),
   .rect (edPad + adv * (2 + e.filter.cursor).toFloat - 1) (rowY 1 + 2) 2 (edLineH - 4) 0 0xbb9af7] ++
  rows.zipIdx.flatMap fun (p, i) =>
    let y := rowY (i + 2)
    (if top + i == e.pick then [Picture.rect 0 y w edLineH 0 0x283457] else []) ++
    [.mono edPad (y + 14) edFont (if top + i == e.pick then 0xc0caf5 else 0x9aa5ce) p]

def view (e : Editor) (w h : Float) : Picture :=
  .group (if e.path.isSome then e.viewFile w h else e.viewFiles w h)

end Editor

def editor : App :=
  App.asking "Editor" ({} : Editor) Editor.heard Editor.view (size := editorSize)
    (titleOf := Editor.title)

end LeanMachine
