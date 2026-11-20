import LeanMachine.Eval.Safepoints
import LeanMachine.Eval.Names

/-! # A REPL's Lean

`startBase` imports the desktop's own Lean in the background, and every
REPL starts from it. `eval` evaluates a line in a REPL's Lean, on the
calling thread, with `runCommands`, and makes the `Env` after it
(`Env.of`), which carries the line's tokenizer and completion. -/

namespace LeanMachine
open Lean Elab

-- The Lean this program was built with, read while it was compiled: the
-- .olean files it imports must come from the Lean linked into it.
elab "buildSysroot%" : term => do
  return mkStrLit (← getBuildDir).toString

def sysroot : System.FilePath := buildSysroot%

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

-- The run on this thread is wrapping up after Lean saw its stop: no
-- safepoint cuts it off from here on (runs.cpp).
@[extern "sv_finishing"] opaque finishing : IO Unit

-- What a REPL's `LeanState` is: Lean's command state, and the index.
structure Held where
  cmd : Command.State
  names : Task NameIndex
  deriving Nonempty

private unsafe def LeanState.ofHeldImpl (h : Held) : LeanState := unsafeCast h
@[implemented_by LeanState.ofHeldImpl] opaque LeanState.ofHeld (h : Held) : LeanState
private unsafe def LeanState.heldImpl (s : LeanState) : Held := unsafeCast s
@[implemented_by LeanState.heldImpl] opaque LeanState.held (s : LeanState) : Held

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
-- characters were put in front of the first line. Where a source of
-- several lines (`several`) went wrong, the line is said too.
def saidOf (msgs : Array Message) (shift : Nat) (several : Bool) : IO (List Said) :=
  msgs.toList.mapM fun m => do
    let text := (← m.data.toString).trimAscii.toString
    let col := if m.pos.line == 1 then m.pos.column - shift else m.pos.column
    let at_ := if several then s!"line {m.pos.line}, col {col}: "
      else if m.pos.column > shift then s!"col {col}: " else ""
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
  let said ← saidOf msgs pre.length (src.contains '\n')
  if stopped then
    return .stopped (said.filter fun | .error e => !(e.splitOn stopDetails).length > 1 | _ => true) true
  return .evaluated said (Env.of { h with cmd := { s with traceState := {} } })

end LeanMachine
