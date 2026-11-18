# Boids

Craig Reynolds' flocking (1987), and the first app made of a folder of
modules: `LeanMachine/Apps/Boids.lean` over the simulation's modules in
`LeanMachine/Apps/Boids/`, all in the namespace `LeanMachine.Boids`.
It follows the first port to Schevana (`apps/boids.ss` as of a24fe98,
itself from Boids in Niva): the same rules, Flake's two for blockers
included, written as idiomatic Lean. The app, `Apps/Boids.lean`, steps
the flock once a frame while it runs ([Using Boids](../../use/boids.md)).

- [Checks that run as it builds](checks-as-it-builds.md)
- [The same bits as Chez](same-bits-as-chez.md)
- [How fast a step is](step-speed.md)
- [At 1000 boids, drawing costs more than the step](drawing-costs-more.md)
- [A vector made to be taken apart isn't made](vectors-not-made.md)
- [Random numbers as state](random-as-state.md)
- [Frames a second, not ms a step](frames-a-second.md)
- [A number beside a vector needs its type](literal-needs-type.md)
- [A compiled simulation under a reloaded app](../reloading/compiled-under-reloaded.md)

[↑ Design](../README.md)
