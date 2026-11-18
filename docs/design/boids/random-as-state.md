# Random numbers as state

Scattering a flock and picking random rules need random numbers, but
the simulation is pure. Lean's `StdGen` is a value: `randNat g lo hi`
gives a number and the next generator.

`uniform lo hi : StateM StdGen Float` threads the generator, so
`Flock.scatter` reads as a loop of random calls (`← uniform 0 w`).
`(Flock.scatter 150 w h).run' gen` is the same flock every time for the
same `gen`. The app will keep the generator in its state, so undo takes
it back along with the flock. The checks pick their flocks from fixed
seeds.

`uniform` takes 53 random bits, a double's precision, and scales them
to [0, 1) exactly with `scaleB`.

[↑ Boids](README.md)
