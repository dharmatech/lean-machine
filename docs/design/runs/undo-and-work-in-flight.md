# Undo and work in flight

The world is a value, but a run going on
is an effect, and undo can't take it back (what a REPL defined, it
can: see below). Undo to a world from before
Enter leaves a run whose outcome the REPL won't wait for (it ignores
outcomes with other tags, and a new run with the same tag replaces
the old). Undo to a world that waited for a run whose outcome came
later brings back a REPL that waits for nothing; Ctrl+C gets it out,
as a stop with nothing to stop is answered at once. Closing a window,
or undoing to before it opened, stops its runs: the loop compares its
runs with the windows after each pass.

[↑ Runs, requests and threads](README.md)
