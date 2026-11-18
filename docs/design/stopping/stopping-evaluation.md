# Stopping evaluation

Compiled code called from the REPL stops as
it did before: `Busy.alloc` and `Busy.polled` within a millisecond
(50 ms now that a stop is offered to Lean code first, below).
So does a loop defined in the REPL that allocates, which the
interpreter runs; one that only does arithmetic on small `Nat`s
(about 250 ns a step interpreted, 60 times compiled code) couldn't be
stopped, like `Busy.spin`, until the REPL put safepoints in what it
compiles (below). A stop that comes while a loop without safepoints
runs (`Busy.spin`, or `quietRaw` below) takes effect at the first
allocation after it, so the run reports that it stopped after the
loop's whole time. RSS grew 1 to 2 MB over 50 stopped evaluations.

[↑ Stopping](README.md)
