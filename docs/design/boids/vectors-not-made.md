# A vector made to be taken apart isn't made

`Vec`'s operations are `@[inline]`. Lean's compiler folds a field of a
structure it has just built into the value it was built from. So
`(b.position - other.position).length2`, in the loop that finds
neighbors, compiles to arithmetic on the four coordinates. The C that
Lean writes for that loop (`.lake/build/ir/LeanMachine/Apps/Boids/Boid.c`)
has no `lean_alloc_ctor`, and neither does `Boid.sees`.

Schevana's port wrote `vec-dist2` on components by hand to get the same
effect. A `vec` for the difference, and the flonums Chez boxed for it,
were most of what a step allocated there.

A `Vec` that is kept, such as a sum or a new velocity, is one small
object with its two doubles stored in it (`lean_ctor_set_float`), not
pointers to boxes.

[↑ Boids](README.md)
