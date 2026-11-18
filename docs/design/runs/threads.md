# Threads

`IO.asTask (prio := .dedicated)` gives each run a thread
of its own, outside Lean's pool of workers: from asking to the end of
a run that does nothing takes about 150 µs. The loop waits on SDL's
queue, not on Lean tasks (Lean's `IO.waitAny` can't wait on SDL too),
so a run's task has a continuation (`IO.mapTask (sync := true)`, run
on the finishing thread once the task has its value) that pushes an
SDL user event; `SDL_PushEvent` may be called from any thread. With
it, the outcome of a run that does nothing is seen 1.2 ms after Enter;
without it, the loop sleeps out its 100 ms wait first. A frame takes
the same 1.1 ms with a run allocating flat out on another thread:
Lean's allocator keeps a heap per thread.

[↑ Runs, requests and threads](README.md)
