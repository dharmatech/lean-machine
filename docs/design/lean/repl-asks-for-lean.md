# A REPL asks for its Lean

Before its first line a REPL has no
`Env`, only "the desktop's own", which the loop imports in the
background. It asks for it as it opens, as the run of an empty line,
and colours nothing until it comes (140 ms after the desktop starts;
a millisecond later). An undo can bring back a REPL whose answer went
to a world that's gone, so a REPL without its Lean asks again each
second.

[↑ Lean inside the desktop](README.md)
