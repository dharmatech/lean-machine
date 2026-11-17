import LeanMachine.Ambient

/-! # Runs: work on threads of its own, and stopping it (runs.cpp)

Not pure: this is the loop's side of `Request`. Each run is a Lean task
with a dedicated thread, which does its work inside a guarded C++ call.
Stopping a run raises its flag; the run's next safepoint (an allocation,
or `poll`) throws, and the guard turns that into `none`. A run that
reaches no safepoint can't be stopped, and finishes. The guard also
lends the run its ambient: the world, and where the apps it opens go.
Evaluating Lean is the loop's to supply (`Services.eval`), so this
module doesn't import Lean. -/

namespace LeanMachine

opaque StopFlagPointed : NonemptyType
def StopFlag := StopFlagPointed.type
instance : Nonempty StopFlag := StopFlagPointed.property

@[extern "sv_flag_new"] opaque StopFlag.new : IO StopFlag
@[extern "sv_flag_raise"] opaque StopFlag.raise (f : @& StopFlag) : IO Unit
-- `some (work ())`, or `none` if a safepoint found `f` raised first.
@[extern "sv_guarded"] opaque guarded (f : @& StopFlag) (work : Unit → String) :
  IO (Option String)
-- Runs `act` with `ambient` lent to it: `some` its value, `none` if a
-- safepoint found `f` raised first, or the error it threw.
@[extern "sv_guarded_io"] opaque guardedIO {α : Type} (f : @& StopFlag)
  (ambient : @& Ambient) (act : IO α) : IO (Option α)

-- What the loop lends runs.
structure Services where
  wake : IO Unit   -- ends the loop's wait for events; any thread may call it
  -- Evaluates a line in a REPL's Lean (`none`: the desktop's own), on the
  -- calling thread: what Lean said, and the Lean after it.
  eval : String → Option Env → IO (List Said × Env)

-- A run going on: the window and tag that asked for it, its flag, its
-- task, which ends with the outcome (`none`: stopped) and the
-- milliseconds it took, and the apps it opened, newest first.
structure Live where
  win : Nat
  tag : Nat
  flag : StopFlag
  task : Task (Except IO.Error (Option Outcome × Nat))
  opened : IO.Ref (List App)

def Live.is (l : Live) (win tag : Nat) : Bool := l.win == win && l.tag == tag

-- Starts a run on a thread of its own: `go` does the work with the run's
-- flag and ambient. `wake` runs once the task has ended, on that thread,
-- so the loop can stop waiting for events and take the outcome.
def Live.start (win tag : Nat) (world : World) (wake : IO Unit)
    (go : StopFlag → Ambient → IO (Option Outcome)) : IO Live := do
  let flag ← StopFlag.new
  let opened ← IO.mkRef []
  let task ← IO.asTask (prio := .dedicated) do
    let t0 ← IO.monoNanosNow
    let r ← go flag { world, opened }
    return (r, ((← IO.monoNanosNow) - t0) / 1000000)
  let _ ← IO.mapTask (fun _ => wake) task (sync := true)
  return { win, tag, flag, task, opened }

-- The events that say how the run ended, and open the apps it opened.
def Live.ended (l : Live) : IO (List Event) := do
  let apps ← l.opened.get
  let done : Event := match l.task.get with
    | .ok (some o, ms) => .done l.win l.tag o ms
    | .ok (none, ms) => .done l.win l.tag .stopped ms
    | .error e => .done l.win l.tag (.failed (toString e)) 0
  return done :: apps.reverse.map (.launch l.win)

-- The runs going on, newest first.
structure Runs where
  live : List Live := []

-- Does what a window's app asked, with `world` the world it asked in. A
-- stop with no run to stop is answered at once, so an app waiting for a
-- run that's gone (after an undo, say) hears that it stopped.
def Runs.handle (rs : Runs) (svc : Services) (world : World) (a : Asked) :
    IO (Runs × List Event) := do
  let start (tag : Nat) (go : StopFlag → Ambient → IO (Option Outcome)) := do
    -- A run with the same tag is replaced: stopped, and its outcome dropped.
    let (old, keep) := rs.live.partition (·.is a.win tag)
    for l in old do l.flag.raise
    let l ← Live.start a.win tag world svc.wake go
    return ({ live := l :: keep : Runs }, ([] : List Event))
  match a.request with
  | .run tag work =>
    start tag fun f _ => return (← guarded f work).map .value
  | .eval tag src env =>
    start tag fun f ambient => guardedIO f ambient do
      let (said, env) ← svc.eval src env
      return Outcome.evaluated said env
  | .stop tag =>
    match rs.live.find? (·.is a.win tag) with
    | some l => l.flag.raise; return (rs, [])
    | none => return (rs, [.done a.win tag .stopped 0])

-- The runs that have ended, as events, oldest first, and the rest.
def Runs.collect (rs : Runs) : IO (Runs × List Event) := do
  let mut live := []
  let mut ended := []
  for l in rs.live.reverse do
    if ← IO.hasFinished l.task then ended := ended ++ (← l.ended)
    else live := l :: live
  return ({ live }, ended)

-- Stops the runs whose window is gone (closed, or undone), and forgets them.
def Runs.keepFor (rs : Runs) (wins : List Nat) : IO Runs := do
  let (keep, gone) := rs.live.partition (wins.contains ·.win)
  for l in gone do l.flag.raise
  return { live := keep }

def Runs.stopAll (rs : Runs) : IO Unit :=
  rs.live.forM (·.flag.raise)

end LeanMachine
