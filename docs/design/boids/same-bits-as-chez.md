# The same bits as Chez

`desktop --bench` steps a flock that any language can make the same
way. Boid `i` starts at (7919 i mod 1200 + 0.5, 6007 i mod 700 + 0.5),
moving at (31 i mod 41 / 10 − 2, 17 i mod 37 / 9 − 2).

Schevana's first port stepped the same flock in plain Chez Scheme
10.4.1. Its simulation was used as it was: `a24fe98:apps/boids.ss`,
lines 1–289, unchanged, with `pi` and `plist-ref` defined first. After
40 frames, the sum of every boid's position had the same 64 bits in
both, in all eight runs: 150, 300, 500 and 1000 boids, under the
default rules and the heaviest.

Both use doubles, with the same operations in the same order. Lean's
arithmetic on `Float` is C's, and its `sqrt` and `cos` are the C
library's. Where the Lean differs from the Scheme, the sums can't tell:
- `-x`, where the Scheme has `(- 0.0 x)` or `(* x -1.0)`, differs at
  most in the sign of a zero.
- The wrap, `x - w * ⌊x / w⌋`, gave what Chez's `mod` gave for every
  boid that wrapped.

[↑ Boids](README.md)
