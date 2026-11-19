import Lean
import LeanMachine.Safepoint

/-! # Safepoints in what the REPL compiles

The REPLs' Lean compiles with one more pass than Lean's own
(`withSafepoints`): `safepointsPass` starts every function it compiles
at a safepoint, so that its loops can be stopped, and an IO function
(`returnsIO`) at one that returns `IO.Error.interrupted` when a stop is
offered (LeanMachine/Safepoint.lean). -/

namespace LeanMachine
open Lean

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

end LeanMachine
