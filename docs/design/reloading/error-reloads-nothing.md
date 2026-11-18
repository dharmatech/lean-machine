# An error reloads nothing

Lean adds a declaration with an error
anyway, with `sorry` in it, and code with `sorry` fails when it runs.
So a reload with any error replaces no app, and the editor marks the
lines. A file's first error doesn't stop Lean: what comes after it is
elaborated too, and all the errors come back at once.

[↑ Reloading](README.md)
