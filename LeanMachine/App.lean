import LeanMachine.Picture
import LeanMachine.Key

/-! # Apps: what runs in a window

An app is a value. It says how it looks at a given size, and what it
becomes after an event, and what it asks the loop to do then. The desktop
holds apps without knowing what kind they are, so any module can add one.

An app can't do work that takes long in its step: the desktop waits for
it. It asks for a run instead: the loop computes a pure function
(`Request.run`) or evaluates Lean (`Request.eval`) on a thread of its
own, and tells the app the outcome as an event (`AppEvent.done`). Apps
stay pure. -/

namespace LeanMachine

-- A time of day, as a tick brings it.
structure TimeOfDay where
  hour : Nat     -- 0 to 23
  minute : Nat
  second : Nat
  deriving BEq, Inhabited, Repr

-- What kind of token Lean's tokenizer read.
inductive TokenKind where
  | keyword    -- a token that is a word: `def`, `fun`, `#eval`
  | symbol     -- any other token: `:=`, `(`, `+`
  | constant   -- an identifier that names a constant here: `Nat.succ`
  | ident      -- any other identifier: a variable, or a name not defined yet
  | number     -- `42`, `0x1f`, `2.5`
  | string     -- a string, a character, or a name: `"hi"`, `'c'`, `` `foo ``
  | comment
  | error      -- where the tokenizer gave up: from there to the end
  deriving BEq, Repr, Inhabited

-- A token of a line: its kind, and where it is, in characters (not bytes).
structure Token where
  start : Nat
  stop : Nat
  kind : TokenKind
  deriving BEq, Repr, Inhabited

-- Where a line of a file starts, for Lean's tokenizer: in code, inside
-- a block comment (`/- … -/`, nested `depth` deep), or inside a string.
-- What the line before it left open.
inductive Carry where
  | code
  | comment (depth : Nat)
  | string
  deriving BEq, Repr, Inhabited

-- Lean's own state for a REPL: the environment its lines are elaborated
-- in, with the scopes they left open (`open`, `namespace`, `variable`).
-- Opaque here, so that the pure modules needn't import Lean; the loop's
-- side (LeanMachine/Eval.lean) knows what it is.
opaque LeanStatePointed : NonemptyType
def LeanState := LeanStatePointed.type
instance : Nonempty LeanState := LeanStatePointed.property

-- A REPL's Lean. A value: a line makes a new one and the old one is
-- still there. It carries what a view or a step may ask of it, as pure
-- functions that Eval.lean makes: a module can't name a function that a
-- module it doesn't import defines, so they come with the value.
structure Env where
  state : LeanState
  -- The tokens of a line, as this Lean's tokenizer reads them, in order.
  tokens : String → Array Token
  -- The tokens of a line of a file that starts where `Carry` says, and
  -- where the next line starts. A comment or a string left open at the
  -- end of the line goes on in the next, instead of being an error.
  tokensFrom : Carry → String → Array Token × Carry
  -- What an identifier being typed (`Nat.su`, `sq`) could become here,
  -- in full and sorted: names of constants, in the namespaces open
  -- here, and keywords.
  complete : String → Array String

-- What Lean said about a line.
inductive Said where
  | info (s : String)      -- `#eval`'s output, say
  | warning (s : String)
  | error (s : String)
  deriving BEq, Repr

-- What Lean said about a place in a file: its line and column, from 0.
structure Remark where
  line : Nat
  col : Nat
  said : Said

-- What an app asks the loop to do. A run is named by a tag the app
-- chooses; its outcome comes back with the tag. A new run with the tag of
-- one still going replaces it.
inductive Request where
  | run (tag : Nat) (work : Unit → String)  -- `work ()`, on a thread of its own
  -- Elaborates `src`, Lean commands or a term to evaluate, in `env`
  -- (`none`: the desktop's own, Init and the desktop's modules).
  | eval (tag : Nat) (src : String) (env : Option Env)
  | stop (tag : Nat)                        -- stop that run at its next safepoint
  -- Files, by their path from the desktop's own folder (where its
  -- lakefile is). These are answered at once, not on a thread of their
  -- own: a run can be cut off midway, and a write mustn't be.
  | read (tag : Nat) (path : String)
  | write (tag : Nat) (path text : String)   -- all of it, in place of what was there
  -- The files under `dir`, at any depth, except in hidden folders
  -- (`.lake`, `.git`), sorted.
  | list (tag : Nat) (dir : String)
  -- Elaborates the text of the Lean file at `path` in the desktop's own
  -- Lean, as Lake would compile it there, on a thread of its own. If
  -- Lean finds no error in it, the apps it defines (its constants of type
  -- `App`) go to the world, which puts each in place of the app of the
  -- same name: in the menu, and in every window opened from it.
  | reload (tag : Nat) (path src : String)

-- How a run ended.
inductive Outcome where
  | value (s : String)     -- `run` finished with this
  | evaluated (said : List Said) (env : Env)  -- `eval` finished: what Lean said, and the new Lean
  -- A stop reached it (or there was no such run). `cleanly`: Lean saw the
  -- stop, as `IO.Error.interrupted` or its own interruption, and the code
  -- on the way unwound itself (`finally` ran), and `said` is what Lean
  -- said before it; otherwise a safepoint cut the run off.
  | stopped (said : List Said := []) (cleanly : Bool := false)
  | failed (why : String)  -- it couldn't run, or a file couldn't be read or written
  | read (text : String)   -- what the file had
  | wrote                  -- the file has the text now
  | listed (paths : List String)  -- from the desktop's folder
  -- `reload` finished: what Lean said, the Lean after the file, and the
  -- names of the apps that went to the world (none if Lean found an
  -- error). The apps themselves can't come back in an outcome: an
  -- `Outcome` is part of an `AppEvent`, which an `App` takes.
  | reloaded (said : List Remark) (env : Env) (apps : List Lean.Name)

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
  -- The wheel turned with the pointer at (x, y): `dy` steps away from
  -- the user (up the page), maybe a fraction of one, from a touchpad.
  | wheel (x y dy : Float)
  -- The window's body is `w` by `h` now: as the window opens, before the
  -- first tick, and whenever its size changes. A view is given the same
  -- size; a step that needs it (how many lines fit) keeps it in its state.
  | resize (w h : Float)
  -- A frame is about to be drawn: 60 a second, while the app animates
  -- and its window isn't minimized. `ms` is a clock's milliseconds, a
  -- clock that only goes forward, from no particular start.
  | frame (ms : Nat)

-- The side of the grip the desktop draws in the bottom right corner of
-- a window's body, over the app: a press there resizes the window. An
-- app can keep what matters out of that corner.
def gripSize : Float := 12

-- `step` returns `none` when the event changes nothing and asks for
-- nothing. It can't return an `App` every time: a type whose every value
-- needs another value of the same type to be built has no values at all.
structure App where
  title : String
  view : Float → Float → Picture          -- at a width and height
  step : AppEvent → Option (App × List Request) := fun _ => none
  size : Float × Float := (414, 229)      -- the body a new window gives it, at first
  -- Whether it wants frames now. While an app in a window that isn't
  -- minimized does, the loop draws 60 frames a second, and the apps that
  -- animate hear `frame` before each.
  animating : Bool := false

instance : Inhabited App := ⟨{ title := "", view := fun _ _ => .group [] }⟩

-- An app made from a state, how an event changes it and what the app asks
-- for then (`none`: no change and nothing asked), and how it looks. The
-- state's type stays inside the app. Only this is `partial`; the functions
-- an app passes it can be total.
-- The title is `title`, unless `titleOf` says what it is in a state;
-- `animating` says whether it wants frames in a state.
partial def App.asking {σ : Type} (title : String) (s : σ)
    (step : σ → AppEvent → Option (σ × List Request))
    (view : σ → Float → Float → Picture)
    (size : Float × Float := (414, 229)) (titleOf : σ → String := fun _ => title)
    (animating : σ → Bool := fun _ => false) : App :=
  { title := titleOf s, view := view s, size, animating := animating s,
    step := fun e => (step s e).map fun (s, asks) =>
      (App.asking title s step view size titleOf animating, asks) }

-- An app that never asks for anything: an event only changes its state
-- (`none`: it doesn't).
def App.of {σ : Type} (title : String) (s : σ)
    (step : σ → AppEvent → Option σ) (view : σ → Float → Float → Picture)
    (size : Float × Float := (414, 229)) (animating : σ → Bool := fun _ => false) : App :=
  App.asking title s (fun s e => (step s e).map (·, [])) view size (animating := animating)

end LeanMachine
