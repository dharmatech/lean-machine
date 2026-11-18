# No state carries over

An app's state is hidden in its closures
(`App.asking`), and the new code can't read the old code's state:
even with the same structure, the reloaded `Editor` is a type of
another environment, and nothing would check a cast between them. So
a reloaded app starts afresh, where its window is. Schevana keeps
state because data outlives the procedures redefined over it. An app
that wanted to keep its state would have to hand it over as plain
data (a `String`, or a type from a module that isn't reloaded).

[↑ Reloading](README.md)
