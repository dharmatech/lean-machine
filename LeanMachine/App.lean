import LeanMachine.Picture

/-! # Apps: what runs in a window

An app is a value. It says how it looks at a given size, and what it
becomes after an event. The desktop holds apps without knowing what kind
they are, so any module can add one. -/

namespace LeanMachine

-- A time of day, as a tick brings it.
structure TimeOfDay where
  hour : Nat     -- 0 to 23
  minute : Nat
  second : Nat
  deriving BEq, Inhabited

-- An event as an app hears it. Positions are in the app's own coordinates:
-- (0, 0) is the top left of its window's body.
inductive AppEvent where
  | press (x y : Float)
  | release (x y : Float)
  | motion (x y : Float)
  | key (code : UInt32)
  | tick (t : TimeOfDay)   -- many times a second, to every app

-- `step` returns `none` when the event changes nothing. It can't return an
-- `App` every time: a type whose every value needs another value of the
-- same type to be built has no values at all.
structure App where
  title : String
  view : Float → Float → Picture          -- at a width and height
  step : AppEvent → Option App := fun _ => none
  size : Float × Float := (414, 229)      -- the body a new window gives it

instance : Inhabited App := ⟨{ title := "", view := fun _ _ => .group [] }⟩

-- An app made from a state, how an event changes it (`none`: it doesn't),
-- and how it looks. The state's type stays inside the app. Only this is
-- `partial`; the functions an app passes it can be total.
partial def App.of {σ : Type} (title : String) (s : σ)
    (step : σ → AppEvent → Option σ) (view : σ → Float → Float → Picture)
    (size : Float × Float := (414, 229)) : App :=
  { title, view := view s, size,
    step := fun e => (step s e).map fun s => App.of title s step view size }

end LeanMachine
