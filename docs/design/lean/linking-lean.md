# Linking Lean

With Lean's interpreter linked in, the executable
goes from 6 MB to 239 MB, and a clean build takes 6.5 s. A headless
run of one frame still takes 0.23 s; importing the REPLs' Lean (Init
and the desktop's modules) takes 125 ms, on a thread of its own, and
RSS goes to 485 MB (483 MB without the apps, since step 7b). Importing all of `Lean` would take 1.6 GB, so the
REPL's Lean doesn't, and neither may any module it imports: that's
why `Env` is opaque in `App.lean` and cast (`unsafeCast`) to Lean's
`Command.State` only in `Eval/Repl.lean`. The .olean files of the Lean the
desktop was built with are read at run time, so `Eval/Repl.lean` notes that
Lean's place as it compiles (`getBuildDir` in a term elaborator) and
passes it to `initSearchPath`; the desktop's own .olean files are
found next to the executable.

[↑ Lean inside the desktop](README.md)
