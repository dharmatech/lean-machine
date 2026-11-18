/-! # Vectors in the plane

A position, a velocity or a push. Arithmetic is through Lean's own
classes, so the rules read as math: `p + v * 4`, `away / away.length`.
The operations are `@[inline]`, so the compiler sees through them: a
vector made only to be taken apart again (`(a - b).length2`) is never
allocated. -/

namespace LeanMachine.Boids

-- π, which Lean's `Float` doesn't have: the closest double, as
-- Schevana's `(* 4 (atan 1))` is.
def pi : Float := 3.141592653589793

structure Vec where
  x : Float
  y : Float
  deriving BEq, Inhabited, Repr

namespace Vec

@[inline] def add (a b : Vec) : Vec := ⟨a.x + b.x, a.y + b.y⟩
@[inline] def sub (a b : Vec) : Vec := ⟨a.x - b.x, a.y - b.y⟩
@[inline] def neg (v : Vec) : Vec := ⟨-v.x, -v.y⟩
@[inline] def scale (v : Vec) (k : Float) : Vec := ⟨v.x * k, v.y * k⟩
@[inline] def shrink (v : Vec) (k : Float) : Vec := ⟨v.x / k, v.y / k⟩

instance : Zero Vec := ⟨⟨0, 0⟩⟩
instance : Add Vec := ⟨add⟩
instance : Sub Vec := ⟨sub⟩
instance : Neg Vec := ⟨neg⟩
instance : HMul Vec Float Vec := ⟨scale⟩
instance : HDiv Vec Float Vec := ⟨shrink⟩

@[inline] def dot (a b : Vec) : Float := a.x * b.x + a.y * b.y

-- The squared length, so comparing distances needs no square root.
@[inline] def length2 (v : Vec) : Float := v.dot v

@[inline] def length (v : Vec) : Float := v.length2.sqrt

-- A quarter turn counterclockwise: square to `v`, as long.
@[inline] def perp (v : Vec) : Vec := ⟨-v.y, v.x⟩

-- The mean of some vectors, the centroid of points: their sum in order,
-- over how many (not empty).
def mean (vs : Array Vec) : Vec := vs.foldl (· + ·) 0 / vs.size.toFloat

end Vec

end LeanMachine.Boids
