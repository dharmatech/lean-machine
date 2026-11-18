# Apps found by their type

The apps a file defines are the
constants it added (`constants.map₂`) whose type is `App`, made values
with `evalConst`. They can't come back in the run's `Outcome`, which
is part of an `AppEvent`, which an `App` takes: an `Outcome` holding an
`App` would make `App` refer to itself on the left of an arrow, and
Lean rejects that (positivity). They come back beside it, in how the
run ended, and the loop hands them to the world as an `Event`, which
apps never see.

[↑ Reloading](README.md)
