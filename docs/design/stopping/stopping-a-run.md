# Stopping a run

Lean has no way to stop a thread: `IO.cancel` only
sets a flag that code must check (`IO.checkCanceled`). Here a run's
thread raises a C++ exception at a safepoint once its flag is up, and
`sv_guarded` catches it at the run's edge, with no change to Lean. The
linker's `--wrap` makes every small allocation a safepoint, from Lean
code compiled anywhere (`Init` and `Std` included, as they're linked
statically) and from Lean's C++ runtime, whose locks are released as
the exception passes; `poll` is the other. `alloc` and `poll` stop within a
millisecond of Ctrl+C (50 ms in the REPL, which offers the stop to
Lean code first: see below); `spin`, a compiled loop on small `Nat`s
that neither allocates nor polls, can't be stopped and runs to its
end. Lean's compiler would have to put polls in the loops it compiles
for that. Unwinding skips the Lean code it leaves, so what that code
held is never freed, but a stop in a loop that drops what it makes
leaks little: RSS stayed at 23 MB over 50 stops. No Lean `finally`
runs on the way, as the exception isn't Lean's; stops that Lean sees
are below.

[↑ Stopping](README.md)
