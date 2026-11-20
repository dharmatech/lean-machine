import LeanMachine.Desktop

/-! # How the tests print what they find

What came back from runs and requests, tokens and the editor's lines,
and windows' edges and places, as short strings. -/

namespace LeanMachine

def Request.show : Request → String
  | .run tag _ => s!"run {tag}"
  | .eval tag src _ => s!"eval {tag} {src.quote}"
  | .stop tag => s!"stop {tag}"
  | .read tag path => s!"read {tag} {path}"
  | .write tag path _ => s!"write {tag} {path}"
  | .list tag dir => s!"list {tag} {dir}"
  | .reload tag path _ => s!"reload {tag} {path}"
  | .copy text => s!"copy {text.quote}"
  | .select text => s!"select {text.quote}"

def Said.show : Said → String
  | .info s => s
  | .warning s => s!"warning: {s}"
  | .error s => s!"error: {s}"

def Outcome.show : Outcome → String
  | .value s => s!"value {s}"
  | .evaluated said _ => s!"said {said.map Said.show}"
  | .stopped said cleanly =>
    s!"stopped{if cleanly then " cleanly" else ""}\
      {if said.isEmpty then "" else s!", said {said.map Said.show}"}"
  | .failed why => s!"failed: {why}"
  | .read s => s!"read {s.length} characters"
  | .wrote => "wrote"
  | .listed paths => s!"listed {paths.length} files"
  | .reloaded said _ apps =>
    s!"reloaded {apps}, said {said.map fun (r : Remark) => s!"{r.line + 1}:{r.col + 1} {r.said.show}"}"

def Event.showDone : Event → String
  | .done win tag o ms => s!"window {win} run {tag}: {o.show}, {ms} ms"
  | .launch win app => s!"window {win} opened {app.title}"
  | .reload win apps => s!"window {win} reloaded {apps.map (·.1)}"
  | _ => "another event"

def TokenKind.show : TokenKind → String
  | .keyword => "keyword" | .symbol => "symbol" | .constant => "constant"
  | .ident => "ident" | .number => "number" | .string => "string"
  | .comment => "comment" | .error => "error"

def Carry.show : Carry → String
  | .code => "code" | .comment d => s!"comment {d}" | .string => "string"

-- The edges named, as "left+bottom".
def Edges.show (e : Edges) : String :=
  let names := [(e.left, "left"), (e.top, "top"), (e.right, "right"), (e.bottom, "bottom")]
  match names.filterMap fun (on, n) => if on then some n else none with
  | [] => "none"
  | ns => "+".intercalate ns

end LeanMachine

namespace LeanMachine.Tests

-- `s` cut into its tokens, each with its kind: `def:keyword`.
def showTokens (s : String) (ts : Array Token) : String :=
  " ".intercalate (ts.toList.map fun t =>
    s!"{String.ofList ((s.toList.drop t.start).take (t.stop - t.start))}:{t.kind.show}")

-- A line of the editor's file, in short: where it starts, its tokens'
-- kinds, and where the next starts.
def showLexed (l : Lexed) : String :=
  let kinds := l.tokens.toList.map (·.kind.show)
  let kinds := kinds.foldr (init := []) fun k ks => if ks.head? == some k then ks else k :: ks
  s!"{l.text.quote}: [{l.carryIn.show}] {" ".intercalate kinds} [→ {l.carry.show}]"

def showFile (e : Editor) : IO Unit := do
  let b := e.buffer
  for l in b.above.reverse ++ b.current :: b.below do
    IO.println s!"    {showLexed l}"

-- A whole number of pixels.
def showNum (f : Float) : String := if f < 0 then s!"-{(-f).toUInt32}" else toString f.toUInt32
def showRect (r : Rect) : String := s!"({showNum r.x}, {showNum r.y}) {showNum r.w} × {showNum r.h}"

end LeanMachine.Tests
