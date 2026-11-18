# Checks that run as it builds

Each Boids module ends with `#guard`s. Lean evaluates them while it
compiles the module, and a check that comes out false is an error
("did not evaluate to `true`"), so the build stops there. They are
Schevana's checks for its Boids:
- the demo's first step, to the last digit (Niva's numbers)
- what the view angle lets a boid see
- that blockers are close and ahead
- the unit steps of the two blocker rules
- that resizing a flock keeps its boids
- that random rules stay within their ranges
- that frames keep every boid on the screen, within the speed limits

Lean's interpreter runs them, so they are kept small: 20 frames of 40
boids, where Schevana checks 50 frames of 150. Each module builds in
under half a second, checks included.

[↑ Boids](README.md)
