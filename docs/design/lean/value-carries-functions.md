# A value that carries its functions

A pure module can't call a
function defined in a module it doesn't import: Lean has no forward
declarations across modules, short of `@[extern "sym"]` in one and
`@[export sym]` in the other, joined by the linker by name and checked
by nothing. The REPL can't import Eval.lean, which imports Lean (the
REPLs' Lean would then import all of Lean, 1.6 GB), so an `Env`
carries `tokens` and `complete` as closures that Eval.lean makes with
it. The REPL's step and view stay pure, as the functions are, and the
type checker sees every call.

[↑ Lean inside the desktop](README.md)
