import LeanMachine.Apps.Boids.Flock

/-! # `--bench`: how fast a step is

`bench` times `Flock.stepOn` on a flock any language can make the same
way, under the default rules and the heaviest, and prints the bits of a
sum of the flock after it, to compare across languages
(docs/design/boids/step-speed.md, docs/design/boids/same-bits-as-chez.md).
Unlike the rest of Boids' simulation, the REPLs' Lean doesn't import
it. -/

namespace LeanMachine.Boids

-- `n` boids placed and set going by whole-number arithmetic, so that
-- any language can make the same flock: Schevana's Boids in Chez steps
-- this one too, and prints the same sums if it steps it the same way.
def benchFlock (n : Nat) : Flock :=
  (Array.range n).map fun i =>
    ⟨⟨((i * 7919) % 1200).toFloat + 0.5, ((i * 6007) % 700).toFloat + 0.5⟩,
     ⟨((i * 31) % 41).toFloat / 10 - 2, ((i * 17) % 37).toFloat / 9 - 2⟩⟩

-- The rules that make a step do the most: every rule on, as strong and
-- as far-seeing as the ranges go. Schevana's benchmarks call them the
-- heaviest.
def heaviest : Rules :=
  { cohesion := 0.2, cohesionRadius := 200, alignment := 1, alignmentRadius := 200,
    separation := 1, separationRadius := 50, viewAngle := 360,
    clearView := 1, backOff := 1, blockerRadius := 100, blockerCone := 180 }

-- The milliseconds a frame's step takes (`Flock.stepOn`, on a field of
-- 1200 × 700): 10 steps, then the mean of 30 more. After them, the bits
-- of the sum of every boid's position, to compare across languages.
def bench : IO Unit := do
  IO.println "Boids: ms a step of Flock.stepOn on 1200 × 700, the mean of 30 after 10"
  let sum (flock : Flock) := flock.foldl (fun s b => s + b.position.x + b.position.y) 0
  for n in [150, 300, 500, 1000] do
    for (name, rules) in [("default", ({} : Rules)), ("heaviest", heaviest)] do
      let steps (flock : Flock) (k : Nat) := k.repeat (·.stepOn rules 1200 700) flock
      let warm := steps (benchFlock n) 10
      let t0 ← IO.monoNanosNow
      let flock := steps warm 30
      let ms := ((← IO.monoNanosNow) - t0).toFloat / 30 / 1e6
      let bits := String.ofList ((Nat.toDigits 16 (sum flock).toBits.toNat).map Char.toUpper)
      IO.println s!"{n} {name}: {ms} ms a step, after 40: {bits}"

end LeanMachine.Boids
