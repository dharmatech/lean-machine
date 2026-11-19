# Pictures nested, not appended

The rules panel's view was first a list of pictures joined with `++`:

```lean
.group ([.rect x 0 panelW (h - barH) 0 0x1f2335, .line x 0 x (h - barH) 1 0x292e42] ++
  rows ++ [.textIn …])
```

It took Lean 103 ms to elaborate, and the window's view, written the
same way, 64 ms. Boids.lean reloaded in 0.56 s. A group inside a group
draws the same:

```lean
.group [.rect x 0 panelW (h - barH) 0 0x1f2335, .line x 0 x (h - barH) 1 0x292e42,
        .group rows, .textIn …]
```

and took 9 ms, and the view too little to show. The reload took
0.42 s.

In a file of its own, a picture of three items took 43 ms with `++`,
5 ms with each list given its type (`([…] : List Picture)`) and 4 ms
nested. The lists' items are `.rect`, `.line`: names whose type comes
from the type expected of them. Most likely, `++` is elaborated as an
operator, whose operands Lean looks at before it settles on the type
they share, so it has no `Picture` to give them at first. A list inside
`.group` has its type from the start.

[↑ Boids](README.md)
