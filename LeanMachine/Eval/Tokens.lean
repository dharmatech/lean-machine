import Lean
import LeanMachine.App

/-! # Tokens, for highlighting

`lexLine`: the tokens of a line as a REPL's Lean reads them, with Lean's
own tokenizer and the environment's token table. `lexFrom`: the tokens
of a line of a file, which may start inside a comment or a string that
the line before left open, and leave one open for the next. -/

namespace LeanMachine
open Lean Elab

-- Can `s` be written as it is, as the last part of a name? (Not
-- `«term_+_»`, not `_private`.)
def isPlainName (s : String) : Bool :=
  match s.toList with
  | c :: cs => isIdFirst c && cs.all isIdRest
  | [] => false

-- A token that is a word, which Lean's editor highlights as a keyword:
-- `def`, `s!`, `#eval`, not `:=` or `λ`.
def isWord (tk : String) : Bool :=
  match tk.toList with
  | c :: cs => c.isAlpha || (c == '#' && (cs.head?.map Char.isAlpha).getD false)
  | [] => false

open Parser in
-- The tokens of `src` as Lean reads them in `cmd`, in order. Lean's
-- tokenizer (`tokenFn`) reads one token at a time with the environment's
-- token table, so notation defined in the REPL is read as the parser
-- will read it, and skips the whitespace and comments after it: any
-- stretch between tokens that isn't blank is a comment. An identifier is
-- a constant if it resolves to one here, as the elaborator would resolve
-- it. Where the tokenizer fails (an unterminated string, a character
-- Lean doesn't know), the rest of the line is an error.
def lexLine (cmd : Command.State) (table : TokenTable) (src : String) : Array Token := Id.run do
  let ictx := mkInputContext src "<line>"
  let scope := cmd.scopes.head!
  let pmctx : ParserModuleContext :=
    { env := cmd.env, options := scope.opts, currNamespace := scope.currNamespace,
      openDecls := scope.openDecls }
  let run (p : ParserFn) (s : ParserState) : ParserState := p.run ictx pmctx table s
  let stop := src.rawEndPos
  let range (stx : Syntax) : Option (String.Pos.Raw × String.Pos.Raw) :=
    match stx.getHeadInfo with
    | .original _ b _ e => some (b, e)
    | _ => none
  let kind : Syntax → TokenKind
    | .atom _ v => if isWord v then .keyword else .symbol
    | .ident _ _ n _ =>
      if (ResolveName.resolveGlobalName cmd.env scope.opts scope.currNamespace
            scope.openDecls n).isEmpty then .ident else .constant
    | .node _ k _ => if k == numLitKind || k == scientificLitKind then .number else .string
    | _ => .ident
  -- Read the tokens, as byte ranges.
  let mut found : Array (String.Pos.Raw × String.Pos.Raw × TokenKind) := #[]
  let mut s := run whitespace (mkParserState src)
  if s.hasError then
    -- A comment at the start that never ends, or a tab.
    let blank := (src.toList.takeWhile Char.isWhitespace).length
    found := found.push (⟨blank⟩, stop, .error)
  for _ in [0:src.length] do
    if s.hasError || s.pos.byteIdx ≥ stop.byteIdx then break
    let start := s.pos
    s := run (tokenFn []) s
    if s.hasError then
      -- A token followed by a comment that never ends, or no token at all.
      let at_ ← match (if s.stxStack.size > 0 then range s.stxStack.back else none) with
        | some (b, e) => found := found.push (b, e, kind s.stxStack.back); pure e
        | none => pure start
      found := found.push (at_, stop, .error)
      break
    let stx := s.stxStack.back
    s := s.popSyntax
    let some (b, e) := range stx | continue
    match stx with
    | .atom _ "/--" | .atom _ "/-!" =>
      -- A doc comment: the tokenizer reads only its start.
      s := run (finishCommentBlock false 1) s
      if s.hasError then found := found.push (b, stop, .error); break
      found := found.push (b, s.pos, .comment)
      s := run whitespace s
    | _ => found := found.push (b, e, kind stx)
  -- Byte positions to characters; the same when the line is ASCII.
  let ascii := src.utf8ByteSize == src.length
  let col (p : String.Pos.Raw) : Nat :=
    if ascii then p.byteIdx else (String.Pos.Raw.extract src 0 p).length
  let mut toks : Array Token := #[]
  let mut last : String.Pos.Raw := 0
  for (b, e, k) in found.push (stop, stop, .comment) do
    let gap := (String.Pos.Raw.extract src last b).toList
    let lead := (gap.takeWhile Char.isWhitespace).length
    if lead < gap.length then
      let trail := (gap.reverse.takeWhile Char.isWhitespace).length
      toks := toks.push { start := col last + lead, stop := col b - trail, kind := .comment }
    if b.byteIdx < e.byteIdx then toks := toks.push { start := col b, stop := col e, kind := k }
    last := e
  return toks

/-! ## Lines of a file: comments and strings that go on -/

-- Where a block comment `depth` deep ends, reading `cs` from `i`: just
-- after its `-/`, or `none` and how deep it is where the line ends.
-- Comments nest, as Lean's do.
partial def commentEnd (cs : Array Char) (i depth : Nat) : Option Nat × Nat :=
  if i + 1 < cs.size then
    let c := cs[i]!
    let d := cs[i + 1]!
    if c == '-' && d == '/' then
      if depth ≤ 1 then (some (i + 2), 0) else commentEnd cs (i + 2) (depth - 1)
    else if c == '/' && d == '-' then commentEnd cs (i + 2) (depth + 1)
    else commentEnd cs (i + 1) depth
  else (none, depth)

-- Where a string ends, reading `cs` from `i`, inside it: just after its
-- closing `"`, or `none` if the line ends first. A backslash escapes the
-- character after it; one at the end of the line goes on into the next,
-- as Lean's string gaps do.
partial def stringEnd (cs : Array Char) (i : Nat) : Option Nat :=
  if i < cs.size then
    match cs[i]! with
    | '\\' => stringEnd cs (i + 2)
    | '"' => some (i + 1)
    | _ => stringEnd cs (i + 1)
  else none

-- Reading code in `cs` from `i`, past blanks and comments that end:
-- where a comment or a string that the line leaves open starts, and
-- what it leaves open. `none` if there's anything else first.
partial def openAt (cs : Array Char) (i : Nat) : Option (Nat × Carry) :=
  if i < cs.size then
    let c := cs[i]!
    if c.isWhitespace then openAt cs (i + 1)
    else if c == '/' && cs[i + 1]? == some '-' then
      match commentEnd cs (i + 2) 1 with
      | (some e, _) => openAt cs e
      | (none, d) => some (i, .comment d)
    else if c == '"' then
      match stringEnd cs (i + 1) with
      | some _ => none
      | none => some (i, .string)
    else none
  else none

-- The tokens of a line of a file that starts where `carry` says, and
-- where the next line starts. Lean's tokenizer can't start inside a
-- comment or a string, so what the line before left open is read to its
-- end here, and the rest of the line by `lexLine`. Where the tokenizer
-- gave up on a comment or a string that doesn't end on this line, that
-- goes on into the next, and is coloured as what it is.
def lexFrom (cmd : Command.State) (table : Parser.TokenTable) (carry : Carry) (src : String) :
    Array Token × Carry := Id.run do
  let cs := src.toList.toArray
  let n := cs.size
  let whole (k : TokenKind) : Array Token := if n == 0 then #[] else #[⟨0, n, k⟩]
  let (pre, start) : Array Token × Nat ← match carry with
    | .code => pure (#[], 0)
    | .comment d => match commentEnd cs 0 d with
      | (none, d) => return (whole .comment, .comment d)
      | (some e, _) => pure (#[⟨0, e, .comment⟩], e)
    | .string => match stringEnd cs 0 with
      | none => return (whole .string, .string)
      | some e => pure (#[⟨0, e, .string⟩], e)
  let rest := if start == 0 then src else String.ofList (cs.extract start n).toList
  let toks := (lexLine cmd table rest).map fun t =>
    { t with start := t.start + start, stop := t.stop + start }
  let some last := toks.back? | return (pre, .code)
  if last.kind != .error then return (pre ++ toks, .code)
  let some (i, left) := openAt cs last.start | return (pre ++ toks, .code)
  -- Comments that end, between the last token and the one left open.
  let between := (List.range' last.start (i - last.start)).filter (!cs[·]!.isWhitespace)
  let closed : Array Token := match between.head?, between.getLast? with
    | some a, some b => #[⟨a, b + 1, .comment⟩]
    | _, _ => #[]
  let kind := if left == .string then TokenKind.string else .comment
  return (pre ++ toks.pop ++ closed ++ #[⟨i, n, kind⟩], left)

end LeanMachine
