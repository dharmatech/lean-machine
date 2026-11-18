import LeanMachine.App
import LeanMachine.Apps.Boids.Flock

/-! # Boids: a flock in a window

Craig Reynolds' Boids (1987), after the first port to Schevana
(`apps/boids.ss`), which came from Boids in Niva
(github.com/dharmatech/boids-niva), in turn inspired by Boids in Aloe
(github.com/dharmatech/2026-09-02-aloe-racket). The blocker rules are
from Gary William Flake's "The Computational Beauty of Nature" (MIT
Press, 1998).

The simulation is in `Apps/Boids/`. Here is the window: a flock over a
field, stepped once a frame while it runs, and a status line under it.
R picks random rules, D the defaults again, S scatters the flock anew,
Up and Down add and take away boids, and Space pauses. A paused flock
doesn't animate, so the desktop goes back to sleeping between events. -/

namespace LeanMachine.Boids

-- The status line's height, under the field.
def barH : Float := 24

-- How many boids a window can have, and how many Up and Down add or
-- take away.
def fewest : Nat := 10
def most : Nat := 2000
def countStep : Nat := 50

-- A Boids window: its flock, the rules it flies by, the generator that
-- scatters it and picks random rules, the body's size, and the frames'
-- pace.
structure State where
  flock : Flock
  rules : Rules := {}
  gen : StdGen
  width : Float := 760
  height : Float := 520 + barH
  running : Bool := true
  -- When the last frame came (ms), and the time between frames,
  -- smoothed over about 20 (0 until there are two).
  lastFrame : Option Nat := none
  frameMs : Float := 0

namespace State

-- The field the flock flies over: the body, above the status line.
def fieldW (s : State) : Float := s.width
def fieldH (s : State) : Float := max 1 (s.height - barH)

-- What `pick` picks with `s`'s generator, and `s` with the generator
-- after it.
def random (s : State) (pick : StateM StdGen α) : α × State :=
  let (a, gen) := pick.run s.gen
  (a, { s with gen })

-- 150 boids scattered over the field, flying by the default rules.
def start : State :=
  let gen := mkStdGen 2026
  let s : State := { flock := #[], gen }
  let (flock, s) := s.random (Flock.scatter 150 s.fieldW s.fieldH)
  { s with flock }

-- `s` with `n` boids, between `fewest` and `most`: the ones it has, or
-- newcomers scattered over the field.
def withCount (s : State) (n : Nat) : State :=
  let (flock, s) := s.random (s.flock.resize (max fewest (min most n)) s.fieldW s.fieldH)
  { s with flock }

-- The time between frames, smoothed, after a frame at `ms`. A gap of
-- more than a quarter second (a pause, a minimized window) isn't a
-- frame's time, and doesn't count.
def smoothed (s : State) (ms : Nat) : Float :=
  match s.lastFrame with
  | some last =>
    let gap := (ms - last).toFloat
    if gap > 250 then s.frameMs
    else if s.frameMs == 0 then gap
    else s.frameMs * 0.95 + gap * 0.05
  | none => s.frameMs

def heard (s : State) : AppEvent → Option State
  | .resize w h => some { s with width := w, height := h }
  | .frame ms =>
    if !s.running then none
    else some { s with flock := s.flock.stepOn s.rules s.fieldW s.fieldH,
                       lastFrame := ms, frameMs := s.smoothed ms }
  | .key k m =>
    if m.ctrl || m.alt then none else
    match k with
    | .char 'r' => let (rules, s) := s.random Rules.random; some { s with rules }
    | .char 'd' => some { s with rules := {} }
    | .char 's' =>
      let (flock, s) := s.random (Flock.scatter s.flock.size s.fieldW s.fieldH)
      some { s with flock }
    | .char ' ' => some { s with running := !s.running, lastFrame := none }
    | .up => some (s.withCount (s.flock.size + countStep))
    | .down => some (s.withCount (s.flock.size - countStep))
    | _ => none
  | _ => none

-- What the status line says: how many, how fast, and the keys.
def status (s : State) : String :=
  let pace :=
    if !s.running then "paused"
    else if s.frameMs == 0 then "starting"
    else s!"{(1000 / s.frameMs).round.toUInt64} fps"
  s!"{s.flock.size} boids · {pace} · r random · d defaults · s scatter · \
    up/down more, fewer · space pause"

end State

-- A dot, with a line toward where it's heading, four steps ahead.
def Boid.picture (b : Boid) : List Picture :=
  let p := b.position
  let tip := p + b.velocity * (4 : Float)
  [.line p.x p.y tip.x tip.y 2 0xf7768e, .circle p.x p.y 3 0xe0af68]

def State.view (s : State) (w h : Float) : Picture :=
  .group [
    .clip 0 0 w (h - barH) (.group (s.flock.foldr (·.picture ++ ·) [])),
    .rect 0 (h - barH) w barH 0 0x16161e,
    .textIn 10 (h - barH) (w - 20 - gripSize) barH 12 .left 0x9aa5ce s.status]

/-! ## Checks, run as the module builds -/

private def press (s : State) (k : Key) : State := (s.heard (.key k {})).getD s

-- Space pauses: no frames are wanted, and one that comes changes
-- nothing. Space again goes on.
#guard !(press .start (.char ' ')).running
#guard ((press .start (.char ' ')).heard (.frame 1000)).isNone
#guard (press (press .start (.char ' ')) (.char ' ')).running

-- A frame steps the flock.
#guard ((State.start.heard (.frame 1000)).map (·.flock != State.start.flock)) == some true

-- R picks other rules, D goes back to the defaults; S scatters as many
-- anew.
#guard (press .start (.char 'r')).rules != {}
#guard (press (press .start (.char 'r')) (.char 'd')).rules == {}
#guard let s := press .start (.char 's'); s.flock.size == 150 && s.flock != State.start.flock

-- Up and Down: 50 more or fewer, never below 10.
#guard (press .start .up).flock.size == 200
#guard (press .start .down).flock.size == 100
#guard ((List.range 5).foldl (fun s _ => press s .down) State.start).flock.size == 10

-- Frames 16 ms apart are 62.5 a second; a gap of a second isn't counted.
#guard
  let frames (s : State) (ms : List Nat) := ms.foldl (fun s t => (s.heard (.frame t)).getD s) s
  let s := frames .start [1000, 1016, 1032]
  s.frameMs == 16 && s.status.startsWith "150 boids · 63 fps" &&
    (frames s [2032]).frameMs == 16

end LeanMachine.Boids

namespace LeanMachine

def boids : App :=
  App.of "Boids" Boids.State.start Boids.State.heard Boids.State.view
    (size := (760, 520 + Boids.barH)) (animating := (·.running))

end LeanMachine
