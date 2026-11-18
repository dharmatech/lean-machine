import LeanMachine.Apps.Boids.Boid
import LeanMachine.Apps.Boids.Rules

/-! # Flocks

A flock is an array of boids, and a step makes a new one: every boid
steered by the same flock, as it was before the step. Then what a
screen adds: the speed limits, and edges that wrap around. -/

namespace LeanMachine.Boids

abbrev Flock := Array Boid

-- `b`'s next state, given the whole flock's current one.
def Boid.steer (b : Boid) (flock : Flock) (rules : Rules) : Boid :=
  let seen (radius fov : Float) := b.neighbors flock radius fov
  -- A rule's push times its weight, worked out only for a weight.
  let push (weight : Float) (rule : Unit → Vec) : Vec :=
    if weight == 0 then 0 else rule () * weight
  let fov := rules.viewAngle
  -- Blockers are in a cone ahead: a boid can't react to what it can't see.
  let cone := min rules.blockerCone fov
  let cohesion := push rules.cohesion fun _ => b.cohere (seen rules.cohesionRadius fov)
  let alignment := push rules.alignment fun _ => b.align (seen rules.alignmentRadius fov)
  let separation := push rules.separation fun _ => b.separate flock rules.separationRadius
  let clearView := push rules.clearView fun _ => b.stepAside (seen rules.blockerRadius cone)
  let backOff := push rules.backOff fun _ => b.backOff (seen rules.blockerRadius cone)
  b.advance (b.velocity + cohesion + alignment + separation + clearView + backOff)

namespace Flock

-- The next flock: every boid steered by the same current one.
def step (flock : Flock) (rules : Rules) : Flock :=
  flock.map (·.steer flock rules)

-- Three boids close together, for the checks.
def demo : Flock :=
  #[⟨⟨0, 0⟩, ⟨1, 0⟩⟩, ⟨⟨1, 1⟩, ⟨0, 1⟩⟩, ⟨⟨2, 0⟩, ⟨1, 1⟩⟩]

end Flock

/-! ## On a screen -/

namespace Boid

-- `b`, moving at least `lo`. Standing still, it has no heading, so it
-- stays put.
def atLeast (b : Boid) (lo : Float) : Boid :=
  let s2 := b.velocity.length2
  if s2 > 0 && s2 < lo * lo then { b with velocity := b.velocity * (lo / s2.sqrt) } else b

-- `b`, moving at most `hi`.
def atMost (b : Boid) (hi : Float) : Boid :=
  let s2 := b.velocity.length2
  if s2 > hi * hi then { b with velocity := b.velocity * (hi / s2.sqrt) } else b

-- Leaving one edge of a `w` × `h` screen brings `b` back at the
-- opposite one.
def wrap (b : Boid) (w h : Float) : Boid :=
  let around (x size : Float) := x - size * (x / size).floor
  { b with position := ⟨around b.position.x w, around b.position.y h⟩ }

end Boid

namespace Flock

-- One frame on a `w` × `h` screen: a step, then the speed limits and the
-- wrap.
def stepOn (flock : Flock) (rules : Rules) (w h : Float) : Flock :=
  (flock.step rules).map fun b => ((b.atLeast rules.minSpeed).atMost rules.maxSpeed).wrap w h

-- `n` boids scattered over a `w` × `h` screen, moving in random
-- directions.
def scatter (n : Nat) (w h : Float) : StateM StdGen Flock :=
  (Array.range n).mapM fun _ => do
    return ⟨⟨← uniform 0 w, ← uniform 0 h⟩, ⟨← uniform (-2) 2, ← uniform (-2) 2⟩⟩

-- `n` boids: the first `n` of `flock`, or all of it and newcomers.
def resize (flock : Flock) (n : Nat) (w h : Float) : StateM StdGen Flock := do
  if n ≤ flock.size then return flock.take n
  return flock ++ (← scatter (n - flock.size) w h)

end Flock

/-! ## Checks, run as the module builds -/

-- The demo's first step, to the last digit: the numbers of Boids in
-- Niva, which Schevana's port checks too. The same operations on
-- doubles, in the same order, give the same bits in all three.
#guard Flock.demo.step {} ==
  #[⟨⟨0.9869999999999999, 0.054⟩, ⟨0.9869999999999999, 0.054⟩⟩,
    ⟨⟨1, 2.002⟩, ⟨0, 1.002⟩⟩,
    ⟨⟨3.003, 0.999⟩, ⟨1.003, 0.999⟩⟩]

-- A resized flock keeps the boids it had.
#guard
  let resized (n : Nat) := (Flock.demo.resize n 100 100).run' (mkStdGen 1) |>.run
  resized 2 == Flock.demo.take 2 && resized 3 == Flock.demo &&
    (resized 5).size == 5 && (resized 5).take 3 == Flock.demo

-- 20 frames of 40 boids keep every boid on the screen, within the speed
-- limits.
#guard
  let rules : Rules := {}
  let frames := (List.range 20).scanl (fun flock _ => flock.stepOn rules 300 200)
    ((Flock.scatter 40 300 200).run' (mkStdGen 7))
  frames.tail.all fun flock => flock.all fun b =>
    let s := b.velocity.length
    0 ≤ b.position.x && b.position.x ≤ 300 && 0 ≤ b.position.y && b.position.y ≤ 200 &&
      rules.minSpeed - 1e-9 ≤ s && s ≤ rules.maxSpeed + 1e-9

end LeanMachine.Boids
