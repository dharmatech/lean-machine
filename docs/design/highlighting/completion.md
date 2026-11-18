# Completion

Lean's own completion (`Lean.Server.Completion`)
isn't a function of an environment and a name: it works from the info
trees of an elaborated file at an LSP position, in the server's
`RequestM`, and answers LSP `CompletionItem`s. What it's made of can
be used as it is: `Meta.allowCompletion` (no auxiliary recursors,
matchers, `noConfusion` or internal names), `isProtected`,
`isPrivateName`, and its rule that a namespace that is also a
constant isn't offered as a namespace (`Picture.brecOn`, which holds
its equation lemmas, would be). The REPL's completion is about 60
lines over those: names by namespace, from every namespace a name
could be resolved from (the current one and those around it, the
root, the open ones), what the REPL defined, and keywords from the
token table (`Trie.findPrefix`). The constants imported are indexed
by namespace once, as the language server caches its "eligible
header declarations" in a global: 38,763 names in 2,993 namespaces,
of 67,499 constants, in 90 ms, in a task of its own after the import,
so the REPLs' Lean is still ready 140 ms after the desktop starts.
Tab then takes 2 µs for `Busy.al` (one name), 130 µs for `List.ma`
(236), 0.9 ms for `Nat.` (2,020): quick enough for the REPL's step, on
the main thread, as a pure function. Most names are theorems' (219 of
the 236 for `List.ma`), so they come after the definitions.
What needs elaboration isn't done: a field after a term (`xs.ma`, which
the type of `xs` decides) and a constructor by the type expected
(`.cir`).

[↑ Highlighting and completion](README.md)
