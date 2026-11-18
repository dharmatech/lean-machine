import LeanMachine.Apps.Boids.Vec

/-! # A boid, and what it makes of the others

Where a boid is, where it's heading, what it sees, and the raw push of
each rule: the flock's steering (`Boid.steer`, in Flock.lean) weighs
them and adds them up.

Reynolds' three rules: cohesion (toward the center of the neighbors),
alignment (toward their mean velocity) and separation (away from any
boid too close). Two more react to blockers, boids close and straight
ahead: clear view steps aside, back off steps away. They come from Gary
William Flake's "The Computational Beauty of Nature" (MIT Press, 1998),
written from his description, not from his (GPL) source. -/

namespace LeanMachine.Boids

-- One bird.
structure Boid where
  position : Vec
  velocity : Vec
  deriving BEq, Inhabited, Repr

namespace Boid

-- Whether `b` sees `other`: it sees `fov` degrees wide, centered on its
-- heading. A boid standing still has no heading, and sees everything.
def sees (b other : Boid) (fov : Float) : Bool :=
  let v := b.velocity
  let h2 := v.length2
  h2 == 0 || fov ≥ 360 ||
    let toOther := other.position - b.position
    let halfAngle := fov / 2 * pi / 180
    v.dot toOther > halfAngle.cos * (h2 * toOther.length2).sqrt

-- The boids of `flock` that `b` sees closer than `r`, not itself.
def neighbors (b : Boid) (flock : Array Boid) (r fov : Float) : Array Boid :=
  let r2 := r * r
  flock.filter fun other =>
    let d2 := (b.position - other.position).length2
    d2 > 0 && d2 < r2 && b.sees other fov

-- Toward the center of `others`.
def cohere (b : Boid) (others : Array Boid) : Vec :=
  if others.isEmpty then 0 else Vec.mean (others.map (·.position)) - b.position

-- Toward the mean velocity of `others`.
def align (b : Boid) (others : Array Boid) : Vec :=
  if others.isEmpty then 0 else Vec.mean (others.map (·.velocity)) - b.velocity

-- Away from every boid of `flock` closer than `r`, seen or not: a boid
-- feels a bump from behind.
def separate (b : Boid) (flock : Array Boid) (r : Float) : Vec :=
  let r2 := r * r
  flock.foldl (init := 0) fun sum other =>
    let away := b.position - other.position
    let d2 := away.length2
    if d2 > 0 && d2 < r2 then sum + away else sum

-- A unit step sideways out from behind each blocker: square to the line
-- between them, on the side `b` is heading.
def stepAside (b : Boid) (blockers : Array Boid) : Vec :=
  blockers.foldl (init := 0) fun sum other =>
    let away := b.position - other.position
    let side := if b.velocity.dot away.perp < 0 then -away.perp else away.perp
    sum + side / away.length

-- A unit step straight away from each blocker.
def backOff (b : Boid) (blockers : Array Boid) : Vec :=
  blockers.foldl (init := 0) fun sum other =>
    let away := b.position - other.position
    sum + away / away.length

-- `b` a step on, moving at `velocity`.
def advance (b : Boid) (velocity : Vec) : Boid :=
  ⟨b.position + velocity, velocity⟩

end Boid

/-! ## Checks, run as the module builds -/

-- A boid at (x, y), heading right.
private def rightward (x y : Float) : Boid := ⟨⟨x, y⟩, ⟨1, 0⟩⟩
private def heading : Boid := rightward 0 0

-- A boid is not its own neighbor.
#guard (heading.neighbors #[heading] 50 360).isEmpty

-- What the view angle lets it see: one boid ahead, one to the side, one
-- behind.
#guard
  let (ahead, side, behind) := (rightward 3 0, rightward 0 3, rightward (-3) 0)
  heading.sees ahead 180 && !heading.sees side 180 && !heading.sees behind 180 &&
    heading.sees side 270 && !heading.sees behind 270 &&
    heading.sees behind 360 && heading.sees ahead 10

-- Blockers are close and ahead: of these, only the one 10 ahead.
#guard
  let flock := #[heading, rightward 10 0, rightward 0 10, rightward (-10) 0, rightward 50 0]
  heading.neighbors flock 40 90 == #[rightward 10 0]

-- Clear view steps one unit aside, back off one unit back. Heading a
-- little upward, the step aside goes up too.
#guard
  let blockers := #[rightward 10 0]
  heading.stepAside blockers == ⟨0, -1⟩ && heading.backOff blockers == ⟨-1, 0⟩ &&
    (Boid.stepAside ⟨⟨0, 0⟩, ⟨1, 0.2⟩⟩ blockers).y > 0

end LeanMachine.Boids
