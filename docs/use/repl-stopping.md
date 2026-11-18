# Stopping a line

Each line runs on a thread of its own, so the desktop
goes on drawing and taking events, and the line can be edited
meanwhile; Ctrl+C stops a run (or clears the line when nothing runs).

`Busy.alloc 100`,
`Busy.polled 1000` and `Busy.spin 1000` are compiled busy work, a few
seconds each; the first two stop at Ctrl+C, `spin` doesn't and
finishes. Every function the REPL compiles starts at a safepoint, so
loops defined there stop too (`set_option leanMachine.safepoints false
in def …` leaves the safepoints out). A stop that reaches IO code
defined in the REPL comes as `IO.Error.interrupted`, so `try`/`finally`
run, and the REPL says "interrupted after …"; anything else is cut off
at a safepoint, past any `finally` ("cut off after …").

How it works: [Stopping](../design/stopping/README.md)

[↑ The REPL](repl.md)
