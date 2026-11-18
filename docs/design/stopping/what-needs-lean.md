# What needs Lean itself

All of the above works without changing
Lean. What would need its compiler or runtime:
- Compiled loops that neither allocate nor poll (`Busy.spin`): the C
  emitter would have to put polls in loops, as the pass does for the
  REPL.
- Cheap safepoints in interpreted code: a check the interpreter made
  itself on entering a function (a thread-local load) would cost a
  nanosecond, not 50.
- Stops as exceptions everywhere, pure code included, so that every
  `finally` runs and what each frame holds is freed: asynchronous
  exceptions, like GHC's `throwTo`, need every frame to unwind the
  Lean way. Today a cut-off is a C++ exception, which skips Lean's
  frames.
- Masking in Lean (GHC's `mask`) with a per-thread stop flag the
  runtime checks, instead of linker wrappers, which miss calls inside
  the runtime's own library and functions that are inlined.
- Blocking calls that end at a stop: `IO.wait`, `Condvar.wait`,
  reading a stream. `IO.cancel` only sets a flag for
  `IO.checkCanceled`, and a cancel token only reaches the elaborator.

[↑ Stopping](README.md)
