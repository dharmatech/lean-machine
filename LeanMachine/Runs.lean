import LeanMachine.Ambient

/-! # Runs: work on threads of its own, and stopping it (runs.cpp)

Not pure: this is the loop's side of `Request`. Each run is a Lean task
with a dedicated thread, which does its work inside a guarded C++ call.
Stopping a run raises its flag and sets its cancel token. Lean code in
an evaluation sees the stop if it can: the elaborator checks the token,
and IO functions compiled in the REPL return `IO.Error.interrupted`
(LeanMachine/Safepoint.lean). Otherwise a safepoint cuts the run off,
and the guard turns that into `none`. A run that reaches no safepoint
can't be stopped, and finishes. The guard also lends the run its
ambient: the world, and where the apps it opens go. Evaluating Lean is
the loop's to supply (`Services.eval`), so this module doesn't import
Lean. -/

namespace LeanMachine

opaque StopFlagPointed : NonemptyType
def StopFlag := StopFlagPointed.type
instance : Nonempty StopFlag := StopFlagPointed.property

@[extern "sv_flag_new"] opaque StopFlag.new : IO StopFlag
@[extern "sv_flag_raise"] opaque StopFlag.raise (f : @& StopFlag) : IO Unit
-- `some (work ())`, or `none` if a safepoint cut it off once `f` was
-- raised.
@[extern "sv_guarded"] opaque guarded (f : @& StopFlag) (work : Unit → String) :
  IO (Option String)
-- Runs `act` with `ambient` lent to it: `some` its value, `none` if a
-- safepoint cut it off once `f` was raised, or the error it threw. A
-- stop is offered to IO code first, as `IO.Error.interrupted`.
@[extern "sv_guarded_io"] opaque guardedIO {α : Type} (f : @& StopFlag)
  (ambient : @& Ambient) (act : IO α) : IO (Option α)

-- What the loop lends runs.
structure Services where
  wake : IO Unit   -- ends the loop's wait for events; any thread may call it
  -- Evaluates a line in a REPL's Lean (`none`: the desktop's own), on the
  -- calling thread, until the token is set: what Lean said, and the Lean
  -- after it, or that it stopped.
  eval : String → Option Env → IO.CancelToken → IO Outcome
  -- Elaborates a file's text in the desktop's own Lean, on the calling
  -- thread, until the token is set: what Lean said, and the apps the
  -- file defines, by name.
  reload : String → String → IO.CancelToken → IO (Outcome × List (Lean.Name × App))
  -- The desktop's own folder, where the paths of file requests start.
  root : System.FilePath

-- `act`'s outcome, or that it failed and why.
def attempt (act : IO Outcome) : IO Outcome :=
  try act catch e => return .failed (toString e)

-- Is `p` a hidden file or folder (`.git`)?
def hidden (p : System.FilePath) : Bool :=
  match p.fileName with
  | some n => n.startsWith "." && n != "." && n != ".."
  | none => false

-- A file request, done on this thread: what was read, written or
-- found, or why it couldn't be. `none` for the other requests.
def fileOutcome (root : System.FilePath) : Request → Option (IO Outcome)
  | .read _ path => some <| attempt do return .read (← IO.FS.readFile (root / path))
  | .write _ path text => some <| attempt do
    -- Written beside it, then renamed over it, so that the file is
    -- never half written, even if the desktop dies midway.
    let p := root / path
    let beside : System.FilePath := p.toString ++ ".saving"
    IO.FS.writeFile beside text
    IO.FS.rename beside p
    return .wrote
  | .list _ dir => some <| attempt do
    let top := if dir.isEmpty || dir == "." then root else root / dir
    let mut paths := #[]
    for p in ← top.walkDir (fun p => return !hidden p) do
      if !hidden p && !(← p.isDir) then
        paths := paths.push (p.toString.drop (root.toString.length + 1)).toString
    return .listed (paths.qsort (· < ·)).toList
  | _ => none

-- How a run ended: its outcome, and the apps a reload made, by name.
abbrev Ending := Outcome × List (Lean.Name × App)

-- A run going on: the window and tag that asked for it, its flag and
-- cancel token, its task, which ends with how it ended (`none`: cut off)
-- and the milliseconds it took, and the apps it opened, newest first.
structure Live where
  win : Nat
  tag : Nat
  flag : StopFlag
  cancel : IO.CancelToken
  task : Task (Except IO.Error (Option Ending × Nat))
  opened : IO.Ref (List App)

def Live.is (l : Live) (win tag : Nat) : Bool := l.win == win && l.tag == tag

-- Asks the run to stop: Lean's elaborator checks the token, safepoints
-- the flag.
def Live.stop (l : Live) : IO Unit := do
  l.flag.raise
  l.cancel.set

-- Starts a run on a thread of its own: `go` does the work with the run's
-- flag, cancel token and ambient. `wake` runs once the task has ended, on
-- that thread, so the loop can stop waiting for events and take the
-- outcome.
def Live.start (win tag : Nat) (world : World) (wake : IO Unit)
    (go : StopFlag → IO.CancelToken → Ambient → IO (Option Ending)) : IO Live := do
  let flag ← StopFlag.new
  let cancel ← IO.CancelToken.new
  let opened ← IO.mkRef []
  let task ← IO.asTask (prio := .dedicated) do
    let t0 ← IO.monoNanosNow
    let r ← go flag cancel { world, opened }
    return (r, ((← IO.monoNanosNow) - t0) / 1000000)
  let _ ← IO.mapTask (fun _ => wake) task (sync := true)
  return { win, tag, flag, cancel, task, opened }

-- The events that say how the run ended, then put the apps a reload
-- made in place of the old, and open the apps it opened.
def Live.ended (l : Live) : IO (List Event) := do
  let apps ← l.opened.get
  let (done, reloaded) : Event × List (Lean.Name × App) := match l.task.get with
    | .ok (some (o, made), ms) => (.done l.win l.tag o ms, made)
    | .ok (none, ms) => (.done l.win l.tag (.stopped [] false) ms, [])
    | .error e => (.done l.win l.tag (.failed (toString e)) 0, [])
  return done :: (if reloaded.isEmpty then [] else [.reload l.win reloaded]) ++
    apps.reverse.map (.launch l.win)

-- The runs going on, newest first.
structure Runs where
  live : List Live := []

-- Does what a window's app asked, with `world` the world it asked in.
-- File requests are answered at once, on this thread. So is a stop with
-- no run to stop, so an app waiting for a
-- run that's gone (after an undo, say) hears that it stopped.
def Runs.handle (rs : Runs) (svc : Services) (world : World) (a : Asked) :
    IO (Runs × List Event) := do
  let start (tag : Nat) (go : StopFlag → IO.CancelToken → Ambient → IO (Option Ending)) := do
    -- A run with the same tag is replaced: stopped, and its outcome dropped.
    let (old, keep) := rs.live.partition (·.is a.win tag)
    for l in old do l.stop
    let l ← Live.start a.win tag world svc.wake go
    return ({ live := l :: keep : Runs }, ([] : List Event))
  match a.request with
  | .run tag work =>
    start tag fun f _ _ => return (← guarded f work).map (.value ·, [])
  | .eval tag src env =>
    start tag fun f cancel ambient => return (← guardedIO f ambient (svc.eval src env cancel)).map (·, [])
  | .reload tag path src =>
    start tag fun f cancel ambient => guardedIO f ambient (svc.reload path src cancel)
  | .read tag _ | .write tag _ _ | .list tag _ =>
    let t0 ← IO.monoNanosNow
    let o ← (fileOutcome svc.root a.request).getD (pure (.failed "not a file request"))
    return (rs, [.done a.win tag o (((← IO.monoNanosNow) - t0) / 1000000)])
  | .stop tag =>
    match rs.live.find? (·.is a.win tag) with
    | some l => l.stop; return (rs, [])
    | none => return (rs, [.done a.win tag (.stopped [] false) 0])

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
  for l in gone do l.stop
  return { live := keep }

def Runs.stopAll (rs : Runs) : IO Unit :=
  rs.live.forM (·.stop)

end LeanMachine
