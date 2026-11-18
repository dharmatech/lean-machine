# Stops that Lean sees

A stop is offered first: the next IO
function compiled in the REPL to start returns `IO.Error.interrupted`,
which Lean code sees as any other error, so its `try`/`catch`/`finally`
run, the elaborator's included. The elaborator also has its own
interruption: `Core.checkInterrupted`, called as it recurses, throws
once the command's cancel token is set, and each run passes one, set
along with its flag, so a slow `#reduce` stops cleanly 10 ms after
Ctrl+C. No command after the one the stop came in is elaborated, and
the REPL keeps the Lean it had. `do try ticks 1000 finally IO.println
"cleaned up"` stops 4 ms after Ctrl+C, with the ticks so far and
"cleaned up". What Lean can't see: a stop that finds pure code (`try
IO.println (quiet …) finally …`) has no IO result to become, so it's
cut off once the offer's 50 ms are out, past the `finally`; and code
that catches the interruption and goes on is cut off 500 ms after it
took it. `IO.sleep` ends at a stop, so the run goes on to its next
safepoint: Lean implements it with `dbgSleep`, which runs.cpp wraps
to sleep in 5 ms slices. Output comes at the end, as before: `#eval`
gathers it.

[↑ Stopping](README.md)
