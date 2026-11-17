import LeanMachine.World

/-! # Runs: work on threads of its own, and stopping it (runs.cpp)

Not pure: this is the loop's side of `Request`. Each run is a Lean task
with a dedicated thread, which computes the work inside a guarded C++
call. Stopping a run raises its flag; the run's next safepoint (an
allocation, or `poll`) throws, and the guard turns that into `none`. A
run that reaches no safepoint can't be stopped, and finishes. -/

namespace LeanMachine

opaque StopFlagPointed : NonemptyType
def StopFlag := StopFlagPointed.type
instance : Nonempty StopFlag := StopFlagPointed.property

@[extern "sv_flag_new"] opaque StopFlag.new : IO StopFlag
@[extern "sv_flag_raise"] opaque StopFlag.raise (f : @& StopFlag) : IO Unit
-- `some (work ())`, or `none` if a safepoint found `f` raised first.
@[extern "sv_guarded"] opaque guarded (f : @& StopFlag) (work : Unit → String) :
  IO (Option String)

-- A run going on: the window and tag that asked for it, its flag, and its
-- task, which ends with the value (`none`: stopped) and the milliseconds
-- it took.
structure Live where
  win : Nat
  tag : Nat
  flag : StopFlag
  task : Task (Except IO.Error (Option String × Nat))

def Live.is (l : Live) (win tag : Nat) : Bool := l.win == win && l.tag == tag

-- Starts `work` on a thread of its own. `wake` runs once the task has
-- ended, on that thread, so the loop can stop waiting for events and
-- take the outcome.
def Live.start (win tag : Nat) (work : Unit → String) (wake : IO Unit) :
    IO Live := do
  let flag ← StopFlag.new
  let task ← IO.asTask (prio := .dedicated) do
    let t0 ← IO.monoNanosNow
    let r ← guarded flag work
    return (r, ((← IO.monoNanosNow) - t0) / 1000000)
  let _ ← IO.mapTask (fun _ => wake) task (sync := true)
  return { win, tag, flag, task }

-- The event that tells the run's window how it ended.
def Live.outcome (l : Live) : Event :=
  match l.task.get with
  | .ok (some s, ms) => .done l.win l.tag (.value s) ms
  | .ok (none, ms) => .done l.win l.tag .stopped ms
  | .error e => .done l.win l.tag (.failed (toString e)) 0

-- The runs going on, newest first.
structure Runs where
  live : List Live := []

-- Does what a window's app asked. A stop with no run to stop is answered
-- at once, so an app waiting for a run that's gone (after an undo, say)
-- hears that it stopped.
def Runs.handle (rs : Runs) (wake : IO Unit) (a : Asked) :
    IO (Runs × List Event) := do
  match a.request with
  | .run tag work =>
    -- A run with the same tag is replaced: stopped, and its outcome dropped.
    let (old, keep) := rs.live.partition (·.is a.win tag)
    for l in old do l.flag.raise
    let l ← Live.start a.win tag work wake
    return ({ live := l :: keep }, [])
  | .stop tag =>
    match rs.live.find? (·.is a.win tag) with
    | some l => l.flag.raise; return (rs, [])
    | none => return (rs, [.done a.win tag .stopped 0])

-- The runs that have ended, as events, oldest first, and the rest.
def Runs.collect (rs : Runs) : IO (Runs × List Event) := do
  let mut live := []
  let mut ended := []
  for l in rs.live.reverse do
    if ← IO.hasFinished l.task then ended := l.outcome :: ended
    else live := l :: live
  return ({ live }, ended.reverse)

-- Stops the runs whose window is gone (closed, or undone), and forgets them.
def Runs.keepFor (rs : Runs) (wins : List Nat) : IO Runs := do
  let (keep, gone) := rs.live.partition (wins.contains ·.win)
  for l in gone do l.flag.raise
  return { live := keep }

def Runs.stopAll (rs : Runs) : IO Unit :=
  rs.live.forM (·.flag.raise)

end LeanMachine
