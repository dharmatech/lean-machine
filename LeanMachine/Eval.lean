import Lean
import LeanMachine.App
import LeanMachine.Safepoint

/-! # Eval: Lean in the desktop's own process

The only module that imports Lean. A REPL's `Env` holds Lean's command
state: the environment and the scopes its lines leave open, and the
tokenizer and completion that read them. The desktop's
own Lean imports Init and the desktop's modules once, in the background,
with `LeanMachine` open; every REPL starts from it.

A line is elaborated on the calling thread, which is a run's, so that a
stop reaches it and the run's ambient is there. `Elab.process` won't do:
it elaborates each command in a task on Lean's pool of threads. Nor will
the older `Frontend.processCommands`, which runs on the calling thread
but loses every message. `runCommands` parses and elaborates itself.

The REPL's Lean compiles with one more pass than Lean's own: every
function it compiles starts at a safepoint, so that its loops can be
stopped, and an IO function returns `IO.Error.interrupted` there when a
stop is offered (LeanMachine/Safepoint.lean). -/

namespace LeanMachine
open Lean Elab

-- The Lean this program was built with, read while it was compiled: the
-- .olean files it imports must come from the Lean linked into it.
elab "buildSysroot%" : term => do
  return mkStrLit (← getBuildDir).toString

def sysroot : System.FilePath := buildSysroot%

-- The desktop's own folder, where its lakefile is, read while this module
-- was compiled (Lake hands Lean the module's full path): the paths of
-- files that apps read and write start there.
elab "sourceRoot%" : term => do
  let file : System.FilePath := ← IO.FS.realPath (← getFileName)
  return mkStrLit ((file.parent.bind (·.parent)).getD ".").toString

def projectRoot : System.FilePath := sourceRoot%

-- What the REPL's Lean imports: the desktop's pure modules, and what
-- code in a run can reach, but not its apps (LeanMachine/Apps/, nor
-- View and Desktop, which import them). An app's file is reloaded in this
-- Lean, and its declarations would clash with themselves here if it had
-- them already. Boids' simulation is here (Flock imports the rest of
-- it), compiled: a reloaded Boids.lean, which is interpreted, steps its
-- flock as fast as the menu's Boids does. The simulation's files can't
-- be reloaded. So are the widgets, which a reloaded app can then use.
def replImports : Array Name :=
  #[`Init, `LeanMachine.Ambient, `LeanMachine.Text, `LeanMachine.Slider,
    `LeanMachine.Apps.Boids.Flock]

/-! ## Safepoints in what the REPL compiles -/

register_option leanMachine.safepoints : Bool := {
  defValue := true
  descr := "start every function the REPL compiles at a safepoint, so that a stop reaches it"
}

section
open Compiler LCNF

-- Is `name`, compiled just now, an IO function: does it take the world
-- last and return what an `IO` action does? Asked of the declaration as
-- the compiler's mono phase saved it, where types are still there.
def returnsIO (name : Name) : CompilerM Bool := do
  let some d ← getLocalDeclAt? name .mono | return false
  let some world := d.params.back? | return false
  unless world.type.isConstOf ``lcVoid do return false
  let rec result : Nat → Expr → Expr
    | n + 1, .forallE _ _ b _ => result n b
    | _, e => e
  let r := result d.params.size d.type
  return r.isAppOf ``EST.Out && r.getAppNumArgs > 0 && (r.getArg! 0).isConstOf ``IO.Error

-- `body`, starting with a safepoint: `safepoint 0`, or for an IO function
-- `if interruptNow 0 then interrupted 0 else body`.
def atSafepoint (io : Bool) (body : Code .impure) : CompilerM (Code .impure) := do
  let zero ← mkLetDecl `zero ImpureType.uint8 (.lit (.uint8 0))
  if !io then
    let p ← mkLetDecl `polled ImpureType.uint8 (.fap ``LeanMachine.safepoint #[.fvar zero.fvarId])
    return .let zero (.let p body)
  let now ← mkLetDecl `stopNow ImpureType.uint8
    (.fap ``LeanMachine.interruptNow #[.fvar zero.fvarId])
  let err ← mkLetDecl `interrupted ImpureType.object
    (.fap ``LeanMachine.interrupted #[.fvar zero.fvarId, .erased])
  let ctor (name : Name) (cidx : Nat) : CtorInfo := { name, cidx, size := 0, usize := 0, ssize := 0 }
  -- In the impure phase a `cases` is named by its discriminant's type in
  -- the machine: a `Bool` is a `UInt8`.
  return .let zero (.let now (.cases ⟨``UInt8, ImpureType.object, now.fvarId,
    #[.ctorAlt (ctor ``Bool.false 0) body,
      .ctorAlt (ctor ``Bool.true 1) (.let err (.return err.fvarId))]⟩))

-- The pass, at the end of the impure phase, after reference counting and
-- boxing: nothing after it moves or drops the safepoints. `_boxed`
-- wrappers only call the function they wrap.
def safepointsPass : Pass where
  name := `leanMachineSafepoints
  phase := .impure
  run decls := do
    unless leanMachine.safepoints.get (← getOptions) do return decls
    decls.mapM fun decl => do
      let .code body := decl.value | return decl
      if isBoxedName decl.name then return decl
      return { decl with value := .code (← atSafepoint (← returnsIO decl.name) body) }

-- `env` with the pass, just before the impure phase saves its
-- declarations. The pass manager is an environment extension's state, so
-- only the REPLs' Lean has the pass, and it needn't import Lean for it.
def withSafepoints (env : Environment) : Environment :=
  passManagerExt.modifyState env (log := .unlogged) fun (installers, pm) =>
    let ps := pm.impurePasses
    let i := (ps.findIdx? (·.name == `saveImpure)).getD ps.size
    (installers, { pm with impurePasses := (ps.extract 0 i).push safepointsPass ++ ps.extract i })

end

/-! ## A REPL's Lean -/

-- The run on this thread is wrapping up after Lean saw its stop: no
-- safepoint cuts it off from here on (runs.cpp).
@[extern "sv_finishing"] opaque finishing : IO Unit

-- The names completion offers from what the REPLs' Lean imports, by the
-- namespace they're in: `Nat` ↦ `succ`, `add`, …; namespaces are names
-- in the namespace around them. Made once, in a task of its own once the
-- desktop's own Lean is imported, and shared by every REPL, as Lean's
-- language server keeps the "eligible header declarations" once.
-- Each name says whether it's a theorem's, which completion offers last.
abbrev NameIndex := Std.HashMap Name (List (String × Bool))

-- What a REPL's `LeanState` is: Lean's command state, and the index.
structure Held where
  cmd : Command.State
  names : Task NameIndex
  deriving Nonempty

private unsafe def LeanState.ofHeldImpl (h : Held) : LeanState := unsafeCast h
@[implemented_by LeanState.ofHeldImpl] opaque LeanState.ofHeld (h : Held) : LeanState
private unsafe def LeanState.heldImpl (s : LeanState) : Held := unsafeCast s
@[implemented_by LeanState.heldImpl] opaque LeanState.held (s : LeanState) : Held

/-! ## Tokens and names, for highlighting and completion -/

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

-- Does completion offer the constant `n`? Not what Lean's own completion
-- leaves out (`Meta.allowCompletion`: auxiliary recursors, matchers,
-- internal names), nor private names, nor names that need «».
def offered (env : Environment) (n : Name) : Bool :=
  match n with
  | .str _ s => isPlainName s && !isPrivateName n && Meta.allowCompletion env n
  | _ => false

-- The index of the constants `env` imported.
def nameIndex (env : Environment) : NameIndex := Id.run do
  let mut index : NameIndex := {}
  let mut spaces : Std.HashSet Name := {}
  for (n, c) in env.constants.map₁ do
    let .str p last := n | continue
    unless offered env n do continue
    index := index.insert p ((last, c matches .thmInfo _) :: index.getD p [])
    -- The namespaces it's in, each once, unless a namespace is also a
    -- constant (`Picture.brecOn`, whose equations are in it), which is
    -- offered or not as a constant, as in Lean's own completion.
    let mut ns := p
    while !spaces.contains ns do
      let .str q s := ns | break
      spaces := spaces.insert ns
      if isPlainName s && !env.contains ns then
        index := index.insert q ((s, false) :: index.getD q [])
      ns := q
  return index

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

-- What `word`, an identifier being typed, could become in `cmd`: `word`
-- with its last part finished as a name in the namespace its other parts
-- name, written from the current namespace, one around it, the root, or
-- an open one, as Lean would resolve it. A protected name needs its
-- namespace even when it's open. With no namespace, keywords too.
-- Sorted, theorems after the rest: they outnumber definitions, and a
-- line more often wants a definition.
def completeIn (cmd : Command.State) (index : Task NameIndex) (table : Parser.TokenTable)
    (word : String) : Array String := Id.run do
  let parts := word.splitOn "."
  let part := parts.getLastD ""
  let qualText := String.ofList (word.toList.take (word.length - part.length))
  let qual : Name := parts.dropLast.foldl Name.str Name.anonymous
  let scope := cmd.scopes.head!
  let env := cmd.env
  let rec around : Name → List Name
    | n@(.str p _) => n :: around p
    | _ => []
  let spaces : List (Name × Bool) :=
    (around scope.currNamespace ++ [Name.anonymous]).map (·, false) ++
    scope.openDecls.filterMap fun | .simple ns _ => some (ns, true) | _ => none
  -- Each name, and whether it's a theorem's.
  let mut out : Std.HashMap String Bool := {}
  for (ns, opened) in spaces do
    let space := ns ++ qual
    let fits (last : String) : Bool :=
      last.startsWith part &&
      !(opened && qual.isAnonymous && isProtected env (.str space last))
    for (last, thm) in index.get.getD space [] do
      if fits last then out := out.insert (qualText ++ last) thm
    -- What the REPL defined.
    for (n, c) in env.constants.map₂ do
      if let .str p last := n then
        if p == space && fits last && offered env n then
          out := out.insert (qualText ++ last) (c matches .thmInfo _)
  if qual.isAnonymous then
    for d in scope.openDecls do
      if let .explicit (.str .anonymous s) _ := d then
        if s.startsWith part then out := out.insert s false
    if !part.isEmpty then
      for tk in table.findPrefix part do
        if isWord tk then out := out.insert tk false
  return (out.toArray.qsort fun (a, t) (b, u) => (!t && u) || (t == u && a < b)).map (·.1)

-- A REPL's Lean, with its tokenizer and completion.
def Env.of (h : Held) : Env :=
  let table := Parser.getTokenTable h.cmd.env
  { state := .ofHeld h, tokens := lexLine h.cmd table, tokensFrom := lexFrom h.cmd table,
    complete := completeIn h.cmd h.names table }

-- Parses and elaborates the commands in `ictx` one at a time, on this
-- thread, from `ps` on, and returns the state after them, what they
-- said, and whether a stop came (`cancel` set): then no command after
-- the one it came in is elaborated. Each command starts with an empty
-- message log (`elabCommandTopLevel` clears it), so what a command said
-- is taken before the next one starts.
partial def elabCommands (ictx : Parser.InputContext) (ps : Parser.ModuleParserState)
    (cancel : IO.CancelToken) (s : Command.State) (said : Array Message := #[]) :
    IO (Command.State × Array Message × Bool) := do
  let scope := s.scopes.head!
  let (cmd, ps', parsed) := Parser.parseCommand ictx
    { env := s.env, options := scope.opts, currNamespace := scope.currNamespace,
      openDecls := scope.openDecls } ps {}
  let ctx : Command.Context :=
    { fileName := ictx.fileName, fileMap := ictx.fileMap, cmdPos := ps.pos,
      snap? := none, cancelTk? := some cancel }
  let r ← (((Command.elabCommandTopLevel cmd) ctx).run s).toIO'
  -- Lean saw the stop, and the code on the way unwound: what's left to
  -- do is this module's, and no safepoint cuts it off.
  if ← cancel.isSet then
    finishing
    let s := match r with | .ok ((), s) => s | .error _ => s
    return (s, said ++ parsed.toArray ++ s.messages.toArray, true)
  let s ← match r with
    | .ok ((), s) => pure s
    | .error e => throw (IO.userError (← e.toMessageData.toString))
  let said := said ++ parsed.toArray ++ s.messages.toArray
  if Parser.isTerminalCommand cmd then return ({ s with messages := {} }, said, false)
  else elabCommands ictx ps' cancel s said

def runCommands (s : Command.State) (src : String) (cancel : IO.CancelToken) :
    IO (Command.State × Array Message × Bool) :=
  elabCommands (Parser.mkInputContext src "<repl>") {} cancel s

-- The desktop's own Lean, and the index of the names it imported, which
-- is ready a little later.
-- `Elab.async` off keeps elaboration on the calling thread; no info trees
-- are kept, as nothing reads them.
unsafe def importBase : IO Held := do
  initSearchPath sysroot [(← IO.appDir) / ".." / "lib" / "lean"]
  enableInitializersExecution
  let env ← importModules (replImports.map ({ module := · })) {}
    (trustLevel := 1024) (loadExts := true)
  let opts := Elab.async.set {} false
  let s := { Command.mkState (withSafepoints env) {} opts with infoState.enabled := false }
  let cmd := (← runCommands s "open LeanMachine" (← IO.CancelToken.new)).1
  return { cmd, names := Task.spawn fun _ => nameIndex env }

-- Starts importing the desktop's own Lean, on a thread of its own.
def startBase : BaseIO (Task (Except IO.Error Held)) :=
  IO.asTask (prio := .dedicated) (unsafe importBase)

-- What Lean said, in the order it said it. `shift` is how many
-- characters were put in front of the line.
def saidOf (msgs : Array Message) (shift : Nat) : IO (List Said) :=
  msgs.toList.mapM fun m => do
    let text := (← m.data.toString).trimAscii.toString
    let at_ := if m.pos.column > shift then s!"col {m.pos.column - shift}: " else ""
    return match m.severity with
      | .information => .info text
      | .warning => .warning s!"{at_}{text}"
      | .error => .error s!"{at_}{text}"

-- Evaluates a line in `env` (`none`: the desktop's own Lean). A line
-- that is a term is evaluated as `#eval` would; anything else is
-- elaborated as commands. Once `cancel` is set, the line stops cleanly
-- if Lean sees it: what Lean said, without the interruption itself.
def eval (base : Task (Except IO.Error Held)) (src : String)
    (env : Option Env) (cancel : IO.CancelToken) : IO Outcome := do
  let h ← match env with
    | some e => pure e.state.held
    | none => IO.ofExcept (← IO.wait base)
  let s := h.cmd
  let isTerm := (Parser.runParserCategory s.env `term src).isOk
  let pre := if isTerm then "#eval " else ""
  let (s, msgs, stopped) ← runCommands s (pre ++ src) cancel
  let said ← saidOf msgs pre.length
  if stopped then
    return .stopped (said.filter fun | .error e => !(e.splitOn stopDetails).length > 1 | _ => true) true
  return .evaluated said (Env.of { h with cmd := { s with traceState := {} } })

/-! ## Reloading an app from its file -/

-- What Lean said about a file, by line and column (from 0).
def remarksOf (msgs : Array Message) : IO (List Remark) :=
  msgs.toList.mapM fun m => do
    let text := (← m.data.toString).trimAscii.toString
    let said := match m.severity with
      | .information => Said.info text
      | .warning => .warning text
      | .error => .error text
    return { line := m.pos.line - 1, col := m.pos.column, said }

-- The module a file in the desktop's folder is: `LeanMachine.Apps.Clock`
-- for `LeanMachine/Apps/Clock.lean`.
def moduleOf (path : System.FilePath) : Name :=
  (path.withExtension "").components.foldl .str .anonymous

#guard moduleOf "LeanMachine/Apps/Boids/Flock.lean" == `LeanMachine.Apps.Boids.Flock

-- The constants of type `App` that `env` has beyond what it imported,
-- by name.
def appsIn (env : Environment) : List Name :=
  let names := env.constants.map₂.toList.filterMap fun (n, c) =>
    if c.type == .const ``App [] && !n.isInternal then some n else none
  (names.toArray.qsort (·.toString < ·.toString)).toList

-- Elaborates the text of a file in the desktop's own Lean, as Lake would
-- compile it there: what Lean said, the Lean after it (for the editor,
-- with `LeanMachine` open, as the desktop's own), and, if Lean found no
-- error, the apps the file defines, by name. The file's header must
-- import only what the desktop's Lean did, and the rest of the file is
-- elaborated from the root namespace, with nothing open. Each reload
-- starts again from the desktop's Lean, so the file's declarations never
-- meet an earlier reload's. A file the desktop's Lean imported can't be
-- reloaded: its declarations are there already, compiled. Stops as
-- `eval` does once `cancel` is set.
def reload (base : Task (Except IO.Error Held)) (path src : String)
    (cancel : IO.CancelToken) : IO (Outcome × List (Name × App)) := do
  let h ← IO.ofExcept (← IO.wait base)
  let have_ := h.cmd.env.header.moduleNames
  let self := moduleOf path
  if have_.contains self then
    return (.failed s!"{self} is compiled into the desktop's Lean: rebuild the desktop to \
      change it", [])
  let ictx := Parser.mkInputContext src path
  let (header, ps, headerSaid) ← Parser.parseHeader ictx
  if headerSaid.hasErrors then
    return (.reloaded (← remarksOf headerSaid.toArray) (Env.of h) [], [])
  let missing := (Elab.headerToImports header).filter (!have_.contains ·.module)
  unless missing.isEmpty do
    return (.failed s!"it imports {", ".intercalate (missing.toList.map (toString ·.module))}, \
      which the desktop's Lean doesn't: only Init and LeanMachine's modules but the apps", [])
  let s : Command.State :=
    { Command.mkState h.cmd.env {} (Elab.async.set {} false) with infoState.enabled := false }
  let (s, msgs, stopped) ← elabCommands ictx ps cancel s
  if stopped then return (.stopped [] true, [])
  let said ← remarksOf msgs
  let env := Env.of { h with cmd := { h.cmd with env := s.env } }
  if msgs.any (·.severity == .error) then return (.reloaded said env [], [])
  let mut apps := #[]
  let mut more := #[]
  for n in appsIn s.env do
    match unsafe s.env.evalConst App {} n (checkMeta := false) with
    | .ok app => apps := apps.push (n, app)
    | .error why => more := more.push { line := 0, col := 0, said := .error s!"{n}: {why}" }
  return (.reloaded (said ++ more.toList) env (apps.toList.map (·.1)), apps.toList)

end LeanMachine
