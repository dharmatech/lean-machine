# Design

A desktop whose world is a value, in Lean 4. Nothing in it is mutated:
an event makes a new world, the view turns a world into a picture, and
one loop at the edge does the I/O.

It grew out of conversations about [Schevana](https://github.com/paveluv/Schevana)
(a Lisp Machine-style desktop in Chez Scheme) on 2026-11-04 and 2026-11-17:
what would such a desktop be in a language with static types, methods by
dot notation, and no mutation? The name is a working title.

## Topics

- [The world and apps](world/README.md)
- [Drawing and input](drawing/README.md)
- [Runs, requests and threads](runs/README.md)
- [Stopping](stopping/README.md)
- [Lean inside the desktop](lean/README.md)
- [Highlighting and completion](highlighting/README.md)
- [The editor](editor/README.md)
- [Reloading](reloading/README.md)
- [Building and linking](building/README.md)

## Reference

- [How it's built](modules.md): the code, module by module
- [What `--test` checks](testing.md)

[↑ Lean Machine](../../README.md)
