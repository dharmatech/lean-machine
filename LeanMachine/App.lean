import LeanMachine.Picture
import LeanMachine.Key

/-! # Apps: what runs in a window

An app is a value. It says how it looks at a given size, and what it
becomes after an event, and what it asks the loop to do then. The desktop
holds apps without knowing what kind they are, so any module can add one.

An app can't do work that takes long in its step: the desktop waits for
it. It asks for a run instead (`Request.run`): the loop computes the work
on a thread of its own and tells the app the outcome as an event
(`AppEvent.done`). Apps stay pure; the work is a pure function. -/

namespace LeanMachine

-- A time of day, as a tick brings it.
structure TimeOfDay where
  hour : Nat     -- 0 to 23
  minute : Nat
  second : Nat
  deriving BEq, Inhabited, Repr

-- What an app asks the loop to do. A run is named by a tag the app
-- chooses; its outcome comes back with the tag. A new run with the tag of
-- one still going replaces it.
inductive Request where
  | run (tag : Nat) (work : Unit → String)  -- `work ()`, on a thread of its own
  | stop (tag : Nat)                        -- stop that run at its next safepoint

-- How a run ended.
inductive Outcome where
  | value (s : String)     -- it finished with this
  | stopped                -- a stop reached it (or there was no such run)
  | failed (why : String)  -- it couldn't run
  deriving BEq, Repr

-- An event as an app hears it. Positions are in the app's own coordinates:
-- (0, 0) is the top left of its window's body.
inductive AppEvent where
  | press (x y : Float)
  | release (x y : Float)
  | motion (x y : Float)
  | key (k : Key) (mods : Mods)
  | text (s : String)      -- typed: a character, or what an input method made
  | tick (t : TimeOfDay)   -- many times a second, to every app
  | done (tag : Nat) (outcome : Outcome) (ms : Nat)  -- a run it asked for ended

-- `step` returns `none` when the event changes nothing and asks for
-- nothing. It can't return an `App` every time: a type whose every value
-- needs another value of the same type to be built has no values at all.
structure App where
  title : String
  view : Float → Float → Picture          -- at a width and height
  step : AppEvent → Option (App × List Request) := fun _ => none
  size : Float × Float := (414, 229)      -- the body a new window gives it

instance : Inhabited App := ⟨{ title := "", view := fun _ _ => .group [] }⟩

-- An app made from a state, how an event changes it and what the app asks
-- for then (`none`: no change and nothing asked), and how it looks. The
-- state's type stays inside the app. Only this is `partial`; the functions
-- an app passes it can be total.
partial def App.asking {σ : Type} (title : String) (s : σ)
    (step : σ → AppEvent → Option (σ × List Request))
    (view : σ → Float → Float → Picture)
    (size : Float × Float := (414, 229)) : App :=
  { title, view := view s, size,
    step := fun e => (step s e).map fun (s, asks) =>
      (App.asking title s step view size, asks) }

-- An app that never asks for anything: an event only changes its state
-- (`none`: it doesn't).
def App.of {σ : Type} (title : String) (s : σ)
    (step : σ → AppEvent → Option σ) (view : σ → Float → Float → Picture)
    (size : Float × Float := (414, 229)) : App :=
  App.asking title s (fun s e => (step s e).map (·, [])) view size

end LeanMachine
