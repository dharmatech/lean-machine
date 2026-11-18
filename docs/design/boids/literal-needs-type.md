# A number beside a vector needs its type

`b.velocity * 4` didn't compile: Lean "failed to synthesize
`HMul Vec Nat Vec`". `Vec` has `HMul Vec Float Vec`, but `*` is
heterogeneous. The vector's type doesn't fix the other side's, so
nothing ties the `4` to `Float`, and a number literal with no other
type is a `Nat`.

`rule () * weight` in `Boid.steer` worked, because `weight` is a
`Float` already. `b.velocity * (4 : Float)` says which type is meant.

[↑ Boids](README.md)
