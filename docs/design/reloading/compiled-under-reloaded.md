# A compiled simulation under a reloaded app

Boids is a folder: `Apps/Boids.lean`, the app, over its simulation in
`Apps/Boids/`. Reloading the whole folder would put the simulation in
Lean's interpreter too, and a flock's step is nearly all arithmetic.
Measured with the folder's files run together and reloaded:

| | a frame's step, 150 boids | 1000 boids | reload |
|---|---:|---:|---:|
| compiled (the menu's Boids) | 0.27 ms | 9 ms | |
| the whole folder, interpreted | 78 ms | 3.3 s | 0.8 s, 1.35 s with its checks |
| Boids.lean alone, over the compiled simulation | 0.27 ms | 9 ms | 0.19 s |

Interpreted, the step takes about 275 times as long. Apps step on the
loop's thread, so the whole desktop would stall with it: at 150 boids
one step is already five frames' time.

So the REPLs' Lean imports the simulation, compiled (`replImports` has
`LeanMachine.Apps.Boids.Flock`, which imports the rest of it), and only
Boids.lean is reloaded. Reloaded code calls the modules it imports as
compiled code, so a reloaded Boids steps its flock as fast as the
menu's does. Only the app's own code is interpreted. Its view, a dot
and a line for each boid, takes 245 µs at 150 boids against 10
compiled, and 1.4 ms at 1000 against 65 µs. That is still less than
drawing it: 3.2 and 12 ms.

The price: the simulation's files can't be reloaded. The REPLs' Lean
has their declarations already
([Lean can't redefine a declaration](no-redefinition.md)), so Ctrl+R
on one is refused with the reason: rebuild the desktop to change it.
In return the REPL can use the simulation:
`(Boids.Flock.demo.stepOn {} 100 100).map (·.position.x)`.

This only works because no name is ever both compiled and reloaded
([The interpreter remembers what's compiled, by name](native-symbol-cache.md)).

[↑ Reloading](README.md)
