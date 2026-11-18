/-! # Picking at random, purely

Lean's `StdGen` is a value: picking a number gives back the next
generator. Threaded through `StateM`, it reads like a random call in
any language, but stays pure, so a flock scattered from the same
generator is the same flock, and undo takes the generator back with
the rest. -/

namespace LeanMachine.Boids

-- A number picked evenly from [lo, hi): 53 random bits, the precision
-- of a double, scaled to [0, 1) exactly.
def uniform (lo hi : Float) : StateM StdGen Float :=
  modifyGet fun g =>
    let (n, g) := randNat g 0 (2 ^ 53 - 1)
    (lo + n.toFloat.scaleB (-53) * (hi - lo), g)

end LeanMachine.Boids
