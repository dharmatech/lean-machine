# The interpreter remembers what's compiled, by name

When Lean's interpreter first calls a declaration, it looks in the
desktop's executable for compiled code under the name the compiler
would have given it: `lp_lean_x2dmachine_` and the mangled name, for
the desktop's own modules. It remembers what it found for the rest of
the process, in one table shared by every Lean in it, keyed by the
declaration's name alone (`g_native_symbol_cache`, in Lean's
`ir_interpreter.cpp`). So the first lookup of a name decides for good:

- A declaration a reload made has no package, so its symbol isn't
  found, and its name is remembered as interpreted. It stays
  interpreted even when called from a Lean that imports the compiled
  module. A name first looked up with Lean's option
  `interpreter.prefer_native` off is remembered the same way.
- A name first found compiled stays compiled. A reload that declared
  it again, with new code, would silently run the old code.

Both happened while measuring Boids' reload
([A compiled simulation under a reloaded app](compiled-under-reloaded.md)).
Reloaded first, the whole folder made `Flock.stepOn` interpreted, and
then a Boids.lean reloaded over the compiled simulation stepped at the
interpreted speed. Done the other way round, the reloaded folder
stepped at the compiled speed: it was running the executable's
`stepOn`, not its own.

The desktop keeps the two apart. The REPLs' Lean imports compiled only
what it never reloads: a reload of a file the REPLs' Lean imported is
refused. Everything it reloads it doesn't import.

[↑ Reloading](README.md)
