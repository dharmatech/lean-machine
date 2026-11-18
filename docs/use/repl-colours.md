# Colours and Tab

The line, and every line entered, is coloured by the
tokens the REPL's Lean reads in it: keywords purple, symbols cyan,
names of constants blue (`sq` turns blue once it's defined), other
identifiers pale, numbers orange, strings green, comments gray, and red
from where Lean's tokenizer gives up (`"unterminated`).

Tab completes the
name before the cursor from the names that REPL's Lean has, its own
definitions and open namespaces included (`Busy.al` → `Busy.alloc`,
`monoAdv` → `monoAdvance`), as far as every name it could become
agrees, and shows them under the line when there's more than one
(`Picture.` shows its ten constructors).

How it works: [Highlighting and completion](../design/highlighting/README.md)

[↑ The REPL](repl.md)
