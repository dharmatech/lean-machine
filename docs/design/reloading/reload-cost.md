# What a reload costs

Clock.lean takes about 95 ms to elaborate,
Placeholder.lean 190, Repl.lean 385, Editor.lean (530 lines) 1.1 s,
Boids.lean 190 (its checks included, which step a flock).
The same files take 90, 170, 370 and 800 ms in a script on one
thread (`lean --run`); why the desktop is slower for the editor
wasn't looked into. The safepoints the REPLs' Lean compiles in cost
little here: Editor.lean without them took as long.

[↑ Reloading](README.md)
