# Work as a pure function

A run is a `Unit → String` an app
builds in its step; the loop calls it on another thread. Lean makes
that safe without asking anything of the app: a closure handed to a
task is marked multi-threaded (`lean_mark_mt`), with everything it
reaches, and from then on its reference counts change atomically. So
a closure that captures something big pays to mark all of it, and the
world's objects it shares stay atomic for good. Because an app only
asks, `--test` can also answer a REPL at once on its own thread
(`hearNow`), with no runs at all.

[↑ Runs, requests and threads](README.md)
