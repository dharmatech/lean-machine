import Tests.Kit

/-! # `--test`: masking

What masking prevents: `Ref.modify` and a mutex cut off midway, with
runs.cpp's masking off, then on (docs/design/stopping/masking.md).
`setMasking` and `refTaken` are in runs.cpp, for this test. -/

namespace LeanMachine.Tests

-- Turns runs.cpp's masking off (0) or on (1).
@[extern "sv_set_masking"] opaque setMasking (on : UInt8) : IO Unit
-- Is the ref emptied by `Ref.take`, and not put back? Reading it would
-- wait for ever.
@[extern "sv_ref_taken"] opaque refTaken {α : Type} (r : @& IO.Ref α) : IO Bool

-- Ten runs, each cut off 70 ms after it starts, while it does `step`
-- over and over (compiled code: the stop isn't offered to it): how many
-- left `stuck` true, and how long the stops took on average.
def cutOffMidway {σ : Type} (fresh : IO σ) (step : σ → Nat → IO Unit)
    (stuck : σ → IO Bool) : IO (Nat × Nat × List σ) := do
  let mut left := 0
  let mut total := 0
  let mut kept := []
  for _ in [0:10] do
    let x ← fresh
    let flag ← StopFlag.new
    let amb : Ambient := { world := start.now, opened := ← IO.mkRef [] }
    let task ← IO.asTask (prio := .dedicated)
      (guardedIO flag amb do for i in [0:1000000000] do step x i)
    IO.sleep 20
    flag.raise
    let t0 ← IO.monoNanosNow
    let _ ← IO.wait task
    total := total + ((← IO.monoNanosNow) - t0) / 1000000
    if ← stuck x then left := left + 1
    kept := x :: kept   -- not freed: a locked mutex mustn't be destroyed
  return (left, total / 10, kept)

-- `Ref.modify` and a mutex, cut off midway with masking off, then on.
def testMasking : IO Unit := do
  -- Most of each step is spent in the function `modify` applies, between
  -- the take and the put.
  let modifyStep (r : IO.Ref (List Nat)) (i : Nat) : IO Unit :=
    r.modify fun l => ((List.range 200).map (· + i + l.length)).take 1
  let lockStep (m : Std.BaseMutex × IO.Ref Nat) (i : Nat) : IO Unit := do
    m.1.lock
    m.2.set ((List.range 200).map (· + i)).length
    m.1.unlock
  let isLocked (m : Std.BaseMutex × IO.Ref Nat) : IO Bool := do
    if ← m.1.tryLock then m.1.unlock; return false else return true
  for masking in [false, true] do
    setMasking (if masking then 1 else 0)
    let (taken, msR, _) ← cutOffMidway (IO.mkRef []) modifyStep refTaken
    let (locked, msM, _) ← cutOffMidway (do return (← Std.BaseMutex.new, ← IO.mkRef 0))
      lockStep isLocked
    IO.println s!"masking {if masking then "on" else "off"}: Ref.modify cut off 10 times \
      left the ref taken {taken} times ({msR} ms a stop); a lock held while cut off \
      left the mutex locked {locked} times ({msM} ms)"
  setMasking 1

end LeanMachine.Tests
