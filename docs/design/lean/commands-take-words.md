# Commands take words

Lean's built-in commands reserve their names
everywhere: `def recall` doesn't parse, because `recall` is a command
(it restates a declaration). A REPL user will hit the same thing;
`«recall»` gets around it.

[↑ Lean inside the desktop](README.md)
