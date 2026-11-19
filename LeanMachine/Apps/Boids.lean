import LeanMachine.App
import LeanMachine.Slider
import LeanMachine.Apps.Boids.Flock

/-! # Boids: a flock in a window

Craig Reynolds' Boids (1987), after the first port to Schevana
(`apps/boids.ss`), which came from Boids in Niva
(github.com/dharmatech/boids-niva), in turn inspired by Boids in Aloe
(github.com/dharmatech/2026-09-02-aloe-racket). The blocker rules are
from Gary William Flake's "The Computational Beauty of Nature" (MIT
Press, 1998).

The simulation is in `Apps/Boids/`. Here is the window: a flock over a
field, stepped once a frame while it runs, its rules beside it, and a
status line under both. The rules are a slider for the count and one
for each setting, as Schevana's rules window had; H hides them, and the
field takes their room. R picks random rules, D the defaults again, S
scatters the flock anew, Up and Down add and take away boids, and Space
pauses. A paused flock doesn't animate, so the desktop goes back to
sleeping between events. -/

namespace LeanMachine.Boids

-- The status line's height, under the field.
def barH : Float := 24

-- How many boids a window can have, and how many Up and Down add or
-- take away.
def fewest : Nat := 10
def most : Nat := 2000
def countStep : Nat := 50

/-! ## The rules beside the field -/

-- The rules' panel, at the right of the body above the status line: its
-- width, the room around its rows, a row's height, and the columns for
-- a row's name and its value, either side of its slider.
def panelW : Float := 360
def pad : Float := 12
def rowH : Float := Slider.height + 6
def labelW : Float := 112
def readoutW : Float := 52

-- A row of the panel: the count, or one of the settings.
inductive Row where
  | count
  | setting (k : Setting)
  deriving BEq

-- Every row, top to bottom: the count, then the settings in the order
-- Schevana's rules window showed them.
def Row.all : List Row := .count :: Setting.all.map .setting

def Setting.label : Setting → String
  | .cohesion => "cohesion"
  | .cohesionRadius => "cohesion radius"
  | .alignment => "alignment"
  | .alignmentRadius => "alignment radius"
  | .separation => "separation"
  | .separationRadius => "separation radius"
  | .viewAngle => "view angle"
  | .clearView => "clear view"
  | .backOff => "back off"
  | .blockerRadius => "blocker radius"
  | .blockerCone => "blocker cone"
  | .minSpeed => "min speed"
  | .maxSpeed => "max speed"

def Row.label : Row → String
  | .count => "boids"
  | .setting k => k.label

-- `v`, not below 0, rounded to `places` digits after the point.
def fixed (places : Nat) (v : Float) : String :=
  let k := 10 ^ places
  let n := (v * k.toFloat).round.toUInt64.toNat
  let frac := toString (n % k)
  if places == 0 then toString n
  else s!"{n / k}.{"".pushn '0' (places - frac.length)}{frac}"

-- A setting's value as its row shows it: speeds to a tenth, angles in
-- whole degrees, weights to four places, and radii in whole pixels.
def Setting.readout (k : Setting) (v : Float) : String :=
  match k with
  | .minSpeed | .maxSpeed => fixed 1 v
  | .viewAngle | .blockerCone => s!"{fixed 0 v}°"
  | _ => if k.isWeight then fixed 4 v else fixed 0 v

-- The field's width in a body `w` wide: all of it, or what the rules
-- leave when they show.
def fieldWidth (rulesShown : Bool) (w : Float) : Float :=
  if rulesShown then max 1 (w - panelW) else w

-- Where row `i`'s slider is in a body `w` wide: between its name and its
-- value. The view draws it there, and a press finds it there.
def sliderBox (w : Float) (i : Nat) : Rect :=
  ⟨w - panelW + pad + labelW, pad + rowH * i.toFloat,
   panelW - 2 * pad - labelW - readoutW, Slider.height⟩

/-! ## The window -/

-- A Boids window: its flock, the rules it flies by, the generator that
-- scatters it and picks random rules, the body's size, the frames'
-- pace, and its rules' panel: whether it shows, and the row whose
-- slider is being dragged.
structure State where
  flock : Flock
  rules : Rules := {}
  gen : StdGen
  width : Float := 760 + panelW
  height : Float := 520 + barH
  running : Bool := true
  -- When the last frame came (ms), and the time between frames,
  -- smoothed over about 20 (0 until there are two).
  lastFrame : Option Nat := none
  frameMs : Float := 0
  rulesShown : Bool := true
  held : Option Row := none

namespace State

-- The field the flock flies over: the body, above the status line and
-- left of the rules.
def fieldW (s : State) : Float := fieldWidth s.rulesShown s.width
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

-- Row `r`'s slider, as `s` has it: its value from the rules or the
-- count, and held if it's the row being dragged. The weights and the
-- count span orders of magnitude, so they go on a cube.
def slider (s : State) (r : Row) : Slider :=
  let held := s.held == some r
  match r with
  | .count =>
    { lo := fewest.toFloat, hi := most.toFloat, value := s.flock.size.toFloat,
      scale := .cube, held }
  | .setting k =>
    { lo := k.range.1, hi := k.range.2, value := s.rules.get k,
      scale := if k.isWeight then .cube else .linear, held }

-- `s` with row `r` set to `v`.
def setRow (s : State) : Row → Float → State
  | .count, v => s.withCount v.round.toUInt64.toNat
  | .setting k, v => { s with rules := s.rules.set k v }

-- Row `r`'s value, as its row shows it.
def readout (s : State) : Row → String
  | .count => toString s.flock.size
  | .setting k => k.readout (s.rules.get k)

-- What a press, a motion or a release does to the rules. The row being
-- dragged hears it, or with none, the row whose slider a press is on.
-- Its slider says what it becomes, and `s` takes the slider's value and
-- whether it's held. The rules and the count stay the only record of
-- the values, so the sliders show them whoever changed them: a drag, a
-- key, or a speed limit pushed by the other.
def pointed (s : State) (e : AppEvent) : Option State := do
  let rows := Row.all.zipIdx
  let (r, i) ← match s.held, e with
    | some r, _ => rows.find? (·.1 == r)
    | none, .press x y => rows.find? fun (_, i) => (sliderBox s.width i).contains x y
    | none, _ => none
  let before := s.slider r
  let after ← before.heard (sliderBox s.width i) e
  let s := if after.value == before.value then s else s.setRow r after.value
  return { s with held := if after.held then some r else none }

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
    | .char 'h' => some { s with rulesShown := !s.rulesShown, held := none }
    | .char ' ' => some { s with running := !s.running, lastFrame := none }
    | .up => some (s.withCount (s.flock.size + countStep))
    | .down => some (s.withCount (s.flock.size - countStep))
    | _ => none
  | e@(.press ..) | e@(.motion ..) | e@(.release ..) =>
    if s.rulesShown then s.pointed e else none
  | _ => none

-- What the status line says: how many, how fast, and the keys.
def status (s : State) : String :=
  let pace :=
    if !s.running then "paused"
    else if s.frameMs == 0 then "starting"
    else s!"{(1000 / s.frameMs).round.toUInt64} fps"
  s!"{s.flock.size} boids · {pace} · r random · d defaults · s scatter · \
    up/down more, fewer · space pause · h rules"

end State

-- A dot, with a line toward where it's heading, four steps ahead.
def Boid.picture (b : Boid) : List Picture :=
  let p := b.position
  let tip := p + b.velocity * (4 : Float)
  [.line p.x p.y tip.x tip.y 2 0xf7768e, .circle p.x p.y 3 0xe0af68]

-- The rules, at the right of a body `w` by `h`: for each row, its name,
-- its slider and its value, and a hint under them.
def State.panel (s : State) (w h : Float) : Picture :=
  let x := w - panelW
  let rows := Row.all.zipIdx.map fun (r, i) =>
    let b := sliderBox w i
    .group [.textIn (x + pad) b.y labelW b.h 12 .left 0x9aa5ce r.label,
            (s.slider r).view b,
            .textIn (b.x + b.w) b.y readoutW b.h 12 .right 0xc0caf5 (s.readout r)]
  .group [.rect x 0 panelW (h - barH) 0 0x1f2335, .line x 0 x (h - barH) 1 0x292e42,
          .group rows,
          .textIn (x + pad) (pad + rowH * Row.all.length.toFloat) (panelW - 2 * pad) rowH 11
            .left 0x565f89 "drag a slider · h hides the rules"]

def State.view (s : State) (w h : Float) : Picture :=
  .group [.clip 0 0 (fieldWidth s.rulesShown w) (h - barH)
            (.group (s.flock.foldr (·.picture ++ ·) [])),
          if s.rulesShown then s.panel w h else .group [],
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

-- The rules show at first, beside a field 760 wide; H hides them, and
-- the field takes the whole body.
#guard State.start.fieldW == 760 && (press .start (.char 'h')).fieldW == 760 + panelW

-- What the rows say at first: the count, and the default rules.
#guard Row.all.map State.start.readout ==
  ["150", "0.0100", "50", "0.0500", "50", "0.0010", "5", "180°", "0.0000", "0.0000",
   "40", "90°", "1.0", "4.0"]

-- `s` after the events `es`, and a press, a motion and a release `t` of
-- the way along row `r`'s slider.
private def pointer (s : State) (es : List AppEvent) : State :=
  es.foldl (fun s e => (s.heard e).getD s) s
private def along (r : Row) (t : Float) : Float × Float :=
  let b := sliderBox State.start.width (Row.all.idxOf r)
  (b.x + Slider.knob + t * (b.w - 2 * Slider.knob), b.y + b.h / 2)
private def pressAt (r : Row) (t : Float) : AppEvent := let (x, y) := along r t; .press x y
private def moveTo (r : Row) (t : Float) : AppEvent := let (x, y) := along r t; .motion x y
private def releaseAt (r : Row) (t : Float) : AppEvent := let (x, y) := along r t; .release x y

-- A press halfway along cohesion's slider, a weight on a cube, sets it
-- to an eighth of its top, and holds it. A motion past the end sets the
-- top; the release lets go, and a motion after it changes nothing.
#guard let s := pointer .start [pressAt (.setting .cohesion) 0.5]
  s.rules.cohesion == 0.025 && s.held == some (.setting .cohesion)
#guard let s := pointer .start [pressAt (.setting .cohesion) 0.5, moveTo (.setting .cohesion) 2,
    releaseAt (.setting .cohesion) 2]
  s.rules.cohesion == 0.2 && s.held == none &&
    (s.heard (moveTo (.setting .cohesion) 0)).isNone

-- Min speed dragged to its top, 5, pushes max speed up to it.
#guard let s := pointer .start [pressAt (.setting .minSpeed) 1]
  s.rules.minSpeed == 5 && s.rules.maxSpeed == 5

-- The count's slider at its start leaves 10 boids.
#guard (pointer .start [pressAt .count 0]).flock.size == 10

-- A press on the field, or where a slider was once H hides the rules,
-- changes nothing.
#guard (State.start.heard (.press 100 100)).isNone
#guard ((press .start (.char 'h')).heard (pressAt (.setting .cohesion) 0.5)).isNone

end LeanMachine.Boids

namespace LeanMachine

def boids : App :=
  App.of "Boids" Boids.State.start Boids.State.heard Boids.State.view
    (size := (760 + Boids.panelW, 520 + Boids.barH)) (animating := (·.running))

end LeanMachine
