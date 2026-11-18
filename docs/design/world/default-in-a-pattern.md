# A default argument is a value in a pattern

`Event.press` took a click count with a default,
`press (x y : Float) (clicks : Nat := 1)`, so every place that builds a
press (the tests have dozens) went on working unchanged. Patterns don't
work the same way. A pattern that leaves the argument out doesn't
match any count: Lean fills in the default, so `.press x y` matches
only `clicks = 1`. In a small test file:

```lean
def f : E → Nat
  | .press _ _ => 0
  | .quit => 1
```

```
error: Missing cases:
(E.press _ _ Nat.zero)
(E.press _ _ (Nat.succ (Nat.succ _)))
```

Lean says so there because the match has no other case. But
`World.commits` and `World.step` end in a catch-all (`| _ => false`,
`| _, _ => world.stepWindows e`). In them, a double click would have
fallen through silently: it wouldn't make an undo step, or wouldn't
pick from the menu. Every pattern on a press names the count, or `_`,
so none of them can fall through this way.

[↑ The world and apps](README.md)
