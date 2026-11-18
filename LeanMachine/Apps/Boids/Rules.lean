import LeanMachine.Apps.Boids.Random

/-! # The rules

Each rule has a weight, how hard it steers, and a radius, how far a
boid looks for it. `viewAngle` is the field of view in degrees,
centered on the heading: 180 sees only ahead, 360 all around. Blockers
are boids closer than `blockerRadius` inside a cone straight ahead,
`blockerCone` degrees wide.

The speed limits belong to the screen, not the simulation (`Flock.step`
leaves them out). With a view of 180°, cohesion pulls stragglers forward
and nothing pulls the leaders back, so speed grows without bound:
classic boids cap it. Back off, unchecked, brakes boids almost to a
standstill: Flake's boids keep a minimum speed. -/

namespace LeanMachine.Boids

-- `{}` is the original settings: see only ahead, barely any separation,
-- and the blocker rules off (their radius and cone are Flake's).
structure Rules where
  cohesion : Float := 0.01
  cohesionRadius : Float := 50
  alignment : Float := 0.05
  alignmentRadius : Float := 50
  separation : Float := 0.001
  separationRadius : Float := 5
  viewAngle : Float := 180
  clearView : Float := 0
  backOff : Float := 0
  blockerRadius : Float := 40
  blockerCone : Float := 90
  minSpeed : Float := 1
  maxSpeed : Float := 4
  deriving BEq, Repr

-- One of the settings, to name it from outside the code: for random
-- rules, and for the sliders a rules window will have.
inductive Setting where
  | cohesion | cohesionRadius | alignment | alignmentRadius
  | separation | separationRadius | viewAngle
  | clearView | backOff | blockerRadius | blockerCone
  | minSpeed | maxSpeed
  deriving BEq, Repr

namespace Setting

-- Every setting, in the order a rules window shows them.
def all : List Setting :=
  [.cohesion, .cohesionRadius, .alignment, .alignmentRadius,
   .separation, .separationRadius, .viewAngle,
   .clearView, .backOff, .blockerRadius, .blockerCone,
   .minSpeed, .maxSpeed]

-- A weight starts at 0, and its useful values span orders of magnitude.
def isWeight : Setting → Bool
  | .cohesion | .alignment | .separation | .clearView | .backOff => true
  | _ => false

-- The values it can take, from the first to the second.
def range : Setting → Float × Float
  | .cohesion => (0, 0.2)
  | .alignment | .separation | .clearView | .backOff => (0, 1)
  | .cohesionRadius | .alignmentRadius => (0, 200)
  | .separationRadius => (0, 50)
  | .viewAngle => (0, 360)
  | .blockerRadius => (0, 100)
  | .blockerCone => (0, 180)
  | .minSpeed => (0, 5)
  | .maxSpeed => (0.5, 10)

end Setting

namespace Rules

def get (r : Rules) : Setting → Float
  | .cohesion => r.cohesion
  | .cohesionRadius => r.cohesionRadius
  | .alignment => r.alignment
  | .alignmentRadius => r.alignmentRadius
  | .separation => r.separation
  | .separationRadius => r.separationRadius
  | .viewAngle => r.viewAngle
  | .clearView => r.clearView
  | .backOff => r.backOff
  | .blockerRadius => r.blockerRadius
  | .blockerCone => r.blockerCone
  | .minSpeed => r.minSpeed
  | .maxSpeed => r.maxSpeed

-- The rules with one setting changed. The speed limits can't cross:
-- setting one past the other pushes the other along.
def set (r : Rules) : Setting → Float → Rules
  | .cohesion, v => { r with cohesion := v }
  | .cohesionRadius, v => { r with cohesionRadius := v }
  | .alignment, v => { r with alignment := v }
  | .alignmentRadius, v => { r with alignmentRadius := v }
  | .separation, v => { r with separation := v }
  | .separationRadius, v => { r with separationRadius := v }
  | .viewAngle, v => { r with viewAngle := v }
  | .clearView, v => { r with clearView := v }
  | .backOff, v => { r with backOff := v }
  | .blockerRadius, v => { r with blockerRadius := v }
  | .blockerCone, v => { r with blockerCone := v }
  | .minSpeed, v => { r with minSpeed := v, maxSpeed := max r.maxSpeed v }
  | .maxSpeed, v => { r with maxSpeed := v, minSpeed := min r.minSpeed v }

-- Rules picked at random, each setting within its range, in order. A
-- weight is picked on a cube, so that small ones come up about as often
-- as on a log scale. Max speed comes after min speed and is picked from
-- it up, so the two never cross.
def random : StateM StdGen Rules :=
  Setting.all.foldlM (init := ({} : Rules)) fun r s => do
    let (lo, hi) := s.range
    let lo := if s == .maxSpeed then max lo r.minSpeed else lo
    let t ← uniform 0 1
    return r.set s (lo + (if s.isWeight then t * t * t else t) * (hi - lo))

end Rules

/-! ## Checks, run as the module builds -/

-- Random rules are rules within the ranges, the speed limits in order.
#guard (List.range 200).all fun seed =>
  let r := Rules.random.run' (mkStdGen seed)
  Setting.all.all (fun s => s.range.1 ≤ r.get s && r.get s ≤ s.range.2) &&
    r.minSpeed ≤ r.maxSpeed

-- Each setting reads back what was set; a speed limit pushes the other.
#guard Setting.all.all fun s => ((({} : Rules).set s 0.75).get s == 0.75)
#guard (({} : Rules).set .minSpeed 6).maxSpeed == 6
#guard (({} : Rules).set .maxSpeed 0.5).minSpeed == 0.5

end LeanMachine.Boids
