# Elaborating on the run's thread

`Lean.Elab.process` elaborates
each command in a task on Lean's pool of threads (the language
server's incremental processor), where the run's stop flag and
ambient aren't. The older `Frontend.processCommands` stays on the
calling thread but loses every message: `elabCommandTopLevel` clears
the log as each command starts, the end of input included. So
`Eval.lean` runs its own loop of `Parser.parseCommand` and
`elabCommandTopLevel`, taking each command's messages, with
`Elab.async` off. `#eval` gathers what the code printed itself
(`withIsolatedStreams`, by thread). A line that parses as a term is
wrapped in `#eval`. Simple lines take 1 to 12 ms.

[↑ Lean inside the desktop](README.md)
