# Lean can't redefine a declaration

An environment only grows:
there's no taking a declaration out or putting another in its place,
which is what reloading is in Schevana (`define` again, and every
caller sees the new one). Reloading Clock.lean in the Lean that
imported it fails ("`LeanMachine.clockFace` has already been
declared"). In a namespace of its own it elaborates, but runs the
wrong code, silently: `t.digits` is dot notation, resolved in the
type's namespace, so the new clock calls the old, compiled `digits`.
A fresh `importModules` of the file's header works, but every import
after the first costs about 400 ms and 370 MB that are never freed
(the first maps the .olean files; later ones read them into memory),
and resets Lean's "run initializers" flag. So the REPLs' Lean doesn't
import the apps at all, and each reload elaborates the file's body
there, from the same starting point: nothing clashes, and memory
stays put. The price: the REPL can't name `clock` or `repl`, only
find them in `(← world).catalog`. A file that imports another app's
file can't be reloaded, nor can Desktop.lean, which imports them all.

[↑ Reloading](README.md)
