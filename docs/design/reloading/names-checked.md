# Names checked as they compile

The menu's items are named with
``` ``clock ``` literals, which Lean resolves and checks as it
compiles Desktop.lean: renaming `clock` without changing the menu
is an error, not a reload that finds nothing. The REPL, without the
apps, uses `` `LeanMachine.clock ``, which nothing checks.

[↑ Reloading](README.md)
