# What safepoints cost

About 50 ns a call of a function defined in
the REPL: that's what the interpreter takes to call compiled code,
whether through the `@[noinline]` wrapper or the extern itself (its
`_boxed` version, which Lean makes for externs with scalar
arguments). On loops that do nothing else, 2 million steps: `quiet`
588 ms with safepoints, 486 ms without (+21%); an empty IO loop 389
and 283 ms (+37%). Code that does more in a call pays less, and
compiled code pays nothing. `set_option leanMachine.safepoints false
in def …` leaves them out of a definition (`register_option` in a
compiled module registers the option as the desktop starts).

[↑ Stopping](README.md)
