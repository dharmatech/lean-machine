# A mutable variable can't be shadowed

The tests thread a desktop through a script by shadowing it, one
`let d := steps d …` after another. `testMinimize` opens windows in a
loop, so it made the desktop mutable for the loop, and went on as
before after it:

```lean
let mut d := start
for (i, k) in [(0 : Nat), 3, 4, 0].zipIdx do
  d := steps d [.menu x y, item x y i]
let d := steps d (button d "REPL")
```

```
error: mutable variable `d` cannot be shadowed
```

Inside a `do` block, a `let` can shadow an ordinary variable, and a
`let mut` can shadow one too, but nothing can shadow a mutable one, to
the end of the block: not a `let` in a nested block, not another
`let mut`. Lean chose that so a reader never wonders
whether `d` after the loop is the one the loop changed. The way
around it is another name for the mutable one (`more`), and
`let d := more` after the loop.

[↑ The world and apps](README.md)
