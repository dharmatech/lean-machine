import LeanMachine.World
import LeanMachine.Busy

/-! # Ambient: what code in a run can reach without being handed it

A REPL's line runs on a thread of its own, and can ask for the world as
it was when Enter was pressed (`world`) and open apps in new windows
(`launch`). Lean has no thread-local or dynamically scoped values, so the
run's guard (runs.cpp) keeps them for the thread while the run lasts.
The REPL's Lean imports this module, with `poll`, so its code can call
these by name. -/

namespace LeanMachine

-- What a run lends the code in it: the world when the run was asked
-- for, and where the apps it opens go, newest first.
structure Ambient where
  world : World
  opened : IO.Ref (List App)

-- The ambient of the run this thread is in, if it's in one.
@[extern "sv_ambient"] opaque ambient? : IO (Option Ambient)

-- The world when Enter was pressed.
def world : IO World := do
  match ← ambient? with
  | some a => return a.world
  | none => throw (IO.userError "`world` is there only in a run")

-- Opens `app` in a new window, by the window that asked, once the run
-- has ended.
def launch (app : App) : IO Unit := do
  match ← ambient? with
  | some a => a.opened.modify (app :: ·)
  | none => throw (IO.userError "`launch` works only in a run")

end LeanMachine
