# A REPL's Lean is a value

Lean's `Command.State`, the environment
and the open scopes, is persistent data, so the REPL keeps it in its
state: a `namespace` or `open` lasts across lines, each REPL has its
own definitions, two REPLs evaluate at once without touching each
other, and undo takes a definition back with the rest of the world.
A stopped line leaves the REPL's Lean as it was.

[↑ Lean inside the desktop](README.md)
