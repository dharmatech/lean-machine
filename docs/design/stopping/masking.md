# Masking

`IO.Ref.modify` is `Ref.take` then `Ref.put`. Take
empties the ref, and a thread that reads an empty ref shared between
threads spins until it's filled (`lean_st_ref_take` and `get` loop on
an atomic exchange). A run cut off between the two leaves the ref
empty for good, and any thread that reads it spins, at full speed, for
ever. The desktop had one: `launch` modifies the run's list of apps,
which the loop reads when the run ends. A mutex held when a run is cut
off stays locked (`Mutex.atomically` unlocks in a `finally`). So
runs.cpp wraps those primitives (`--wrap` of `lean_st_ref_take`, `put`,
and the mutexes' lock, try-lock and unlock) to count what each thread
holds; a stop that comes meanwhile waits, and the put or unlock that
ends the region is a safepoint. It reaches interpreted code too: the
interpreter calls externs through compiled code (their `_boxed`
versions), which calls the wrapped functions. Compiled code cut off
midway, ten times each: without masking the ref was left taken 6 to 9
times and the mutex locked 8 or 9 times (over three runs of the test);
with it, never, and the stops took no longer (50 ms). A stop is still offered to IO code that holds a
mutex (the `finally` unlocks it), not to code that holds a taken ref.
A long critical section holds a stop off until it ends.

[↑ Stopping](README.md)
