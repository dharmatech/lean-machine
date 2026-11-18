# Names that resolve

`ResolveName.resolveGlobalName` is a pure
function of an environment, options, the current namespace and the
open declarations, so an identifier it resolves is drawn as a
constant: the REPL's own definitions, names reached through `open`,
and a constant followed by fields. Lean's editor tells more
apart, variables, functions, types, from the info trees the
elaborator fills (`Lean.Server.FileWorker.SemanticHighlighting`).
That takes a line that elaborates, with info trees on (the REPL keeps
them off), in the language server's request monad: possible after
Enter, not at each keystroke.

[↑ Highlighting and completion](README.md)
