# Boids

Craig Reynolds' flocking (1987), and the first app made of a folder of
modules: `LeanMachine/Apps/Boids/`, in the namespace `LeanMachine.Boids`.
It follows the first port to Schevana (`apps/boids.ss` as of a24fe98,
itself from Boids in Niva): the same rules, Flake's two for blockers
included, written as idiomatic Lean. So far there is only the
simulation. The app comes once the loop gives apps frames.

- [Checks that run as it builds](checks-as-it-builds.md)
- [The same bits as Chez](same-bits-as-chez.md)
- [How fast a step is](step-speed.md)
- [A vector made to be taken apart isn't made](vectors-not-made.md)
- [Random numbers as state](random-as-state.md)

[↑ Design](../README.md)
