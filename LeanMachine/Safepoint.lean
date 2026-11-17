/-! # Safepoints: where a stop reaches Lean code

A run is stopped at a safepoint (runs.cpp). Every small allocation is
one; so is `poll`, which compiled code calls where it likes; and the
REPL's Lean puts a call to `safepoint` or `interruptNow` at the start of
every function it compiles (LeanMachine/Eval.lean), so that its loops
can be stopped too.

A stop is first offered to IO code compiled in the REPL as
`IO.Error.interrupted`, which Lean's `try`/`catch`/`finally` see; if
none takes it within 50 ms, the next safepoint of any kind cuts the run
off, past the Lean code on the way. The REPL's Lean imports this module,
through LeanMachine.Busy, and the interpreter calls the compiled code
here. -/

namespace LeanMachine

-- A safepoint: `poll x` is `x`, unless the run it's in has been asked to
-- stop. Not inlined, so code elaborated later can call it by name.
@[extern "sv_poll"] opaque pollCore (x : Nat) : Nat
@[noinline] def poll (x : Nat) : Nat := pollCore x

-- The safepoint at the start of a pure function compiled in the REPL. A
-- scalar in and out: nothing to count references of.
@[extern "sv_safepoint"] opaque safepointCore (x : UInt8) : UInt8
@[noinline] def safepoint (x : UInt8) : UInt8 := safepointCore x

-- The safepoint at the start of an IO function compiled in the REPL:
-- true if a stop is to be taken here, as `interrupted`.
@[extern "sv_interrupt_now"] opaque interruptNowCore (x : UInt8) : Bool
@[noinline] def interruptNow (x : UInt8) : Bool := interruptNowCore x

-- What a stop says when Lean code sees it.
def stopDetails : String := "the run was asked to stop"

-- A stop, as the error an IO function compiled in the REPL returns.
@[noinline] def interrupted (_ : UInt8) : IO Unit :=
  throw (.interrupted "" 0 stopDetails)

end LeanMachine
