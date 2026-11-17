import Lean
import LeanMachine.App
import LeanMachine.Safepoint

/-! # Eval: Lean in the desktop's own process

The only module that imports Lean. A REPL's `Env` is Lean's command
state: the environment and the scopes its lines leave open. The desktop's
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

-- What the REPL's Lean imports: the desktop's pure modules, and what
-- code in a run can reach.
def replImports : Array Name :=
  #[`Init, `LeanMachine.View, `LeanMachine.Ambient]

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

private unsafe def Env.ofStateImpl (s : Command.State) : Env := unsafeCast s
@[implemented_by Env.ofStateImpl] opaque Env.ofState (s : Command.State) : Env
private unsafe def Env.toStateImpl (e : Env) : Command.State := unsafeCast e
@[implemented_by Env.toStateImpl] opaque Env.toState (e : Env) : Command.State

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

-- The desktop's own Lean. `Elab.async` off keeps elaboration on the
-- calling thread; no info trees are kept, as nothing reads them.
unsafe def importBase : IO Command.State := do
  initSearchPath sysroot [(← IO.appDir) / ".." / "lib" / "lean"]
  enableInitializersExecution
  let env ← importModules (replImports.map ({ module := · })) {}
    (trustLevel := 1024) (loadExts := true)
  let opts := Elab.async.set {} false
  let s := { Command.mkState (withSafepoints env) {} opts with infoState.enabled := false }
  return (← runCommands s "open LeanMachine" (← IO.CancelToken.new)).1

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
-- elaborated as commands. Once `cancel` is set, the line stops cleanly
-- if Lean sees it: what Lean said, without the interruption itself.
def eval (base : Task (Except IO.Error Command.State)) (src : String)
    (env : Option Env) (cancel : IO.CancelToken) : IO Outcome := do
  let s ← match env with
    | some e => pure e.toState
    | none => IO.ofExcept (← IO.wait base)
  let isTerm := (Parser.runParserCategory s.env `term src).isOk
  let pre := if isTerm then "#eval " else ""
  let (s, msgs, stopped) ← runCommands s (pre ++ src) cancel
  let said ← saidOf msgs pre.length
  if stopped then
    return .stopped (said.filter fun | .error e => !(e.splitOn stopDetails).length > 1 | _ => true) true
  return .evaluated said (Env.ofState { s with traceState := {} })

end LeanMachine
