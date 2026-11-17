import Lean
import LeanMachine.App

/-! # Eval: Lean in the desktop's own process

The only module that imports Lean. A REPL's `Env` is Lean's command
state: the environment and the scopes its lines leave open. The desktop's
own Lean imports Init and the desktop's modules once, in the background,
with `LeanMachine` open; every REPL starts from it.

A line is elaborated on the calling thread, which is a run's, so that a
stop reaches it and the run's ambient is there. `Elab.process` won't do:
it elaborates each command in a task on Lean's pool of threads. Nor will
the older `Frontend.processCommands`, which runs on the calling thread
but loses every message. `runCommands` parses and elaborates itself. -/

namespace LeanMachine
open Lean Elab

-- The Lean this program was built with, read while it was compiled: the
-- .olean files it imports must come from the Lean linked into it.
elab "buildSysroot%" : term => do
  return mkStrLit (← getBuildDir).toString

def sysroot : System.FilePath := buildSysroot%

-- What the REPL's Lean imports: the desktop's pure modules, and what
-- code in a run can reach.
def replImports : Array Name :=
  #[`Init, `LeanMachine.View, `LeanMachine.Ambient]

private unsafe def Env.ofStateImpl (s : Command.State) : Env := unsafeCast s
@[implemented_by Env.ofStateImpl] opaque Env.ofState (s : Command.State) : Env
private unsafe def Env.toStateImpl (e : Env) : Command.State := unsafeCast e
@[implemented_by Env.toStateImpl] opaque Env.toState (e : Env) : Command.State

-- Parses and elaborates the commands in `ictx` one at a time, on this
-- thread, from `ps` on, and returns the state after them and what they
-- said. Each command starts with an empty message log
-- (`elabCommandTopLevel` clears it), so what a command said is taken
-- before the next one starts.
partial def elabCommands (ictx : Parser.InputContext) (ps : Parser.ModuleParserState)
    (s : Command.State) (said : Array Message := #[]) :
    IO (Command.State × Array Message) := do
  let scope := s.scopes.head!
  let (cmd, ps', parsed) := Parser.parseCommand ictx
    { env := s.env, options := scope.opts, currNamespace := scope.currNamespace,
      openDecls := scope.openDecls } ps {}
  let ctx : Command.Context :=
    { fileName := ictx.fileName, fileMap := ictx.fileMap, cmdPos := ps.pos,
      snap? := none, cancelTk? := none }
  let s ← match ← (((Command.elabCommandTopLevel cmd) ctx).run s).toIO' with
    | .ok ((), s) => pure s
    | .error e => throw (IO.userError (← e.toMessageData.toString))
  let said := said ++ parsed.toArray ++ s.messages.toArray
  if Parser.isTerminalCommand cmd then return ({ s with messages := {} }, said)
  else elabCommands ictx ps' s said

def runCommands (s : Command.State) (src : String) :
    IO (Command.State × Array Message) :=
  elabCommands (Parser.mkInputContext src "<repl>") {} s

-- The desktop's own Lean. `Elab.async` off keeps elaboration on the
-- calling thread; no info trees are kept, as nothing reads them.
unsafe def importBase : IO Command.State := do
  initSearchPath sysroot [(← IO.appDir) / ".." / "lib" / "lean"]
  enableInitializersExecution
  let env ← importModules (replImports.map ({ module := · })) {}
    (trustLevel := 1024) (loadExts := true)
  let opts := Elab.async.set {} false
  let s := { Command.mkState env {} opts with infoState.enabled := false }
  return (← runCommands s "open LeanMachine").1

-- Starts importing the desktop's own Lean, on a thread of its own.
def startBase : BaseIO (Task (Except IO.Error Command.State)) :=
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
-- elaborated as commands.
def eval (base : Task (Except IO.Error Command.State)) (src : String)
    (env : Option Env) : IO (List Said × Env) := do
  let s ← match env with
    | some e => pure e.toState
    | none => IO.ofExcept (← IO.wait base)
  let isTerm := (Parser.runParserCategory s.env `term src).isOk
  let pre := if isTerm then "#eval " else ""
  let (s, msgs) ← runCommands s (pre ++ src)
  return (← saidOf msgs pre.length, Env.ofState { s with traceState := {} })

end LeanMachine
