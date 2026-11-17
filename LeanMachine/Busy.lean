import LeanMachine.Safepoint

/-! # Busy work: compiled loops to run, and stop

Each takes `n` million steps, and they differ only in where a stop can
reach them (LeanMachine/Safepoint.lean): every small allocation, and
`poll`. Pure. The REPL's Lean imports this module, so `Busy.alloc 100`
there runs this compiled code. -/

namespace LeanMachine

def Busy.million : Nat := 1000000

-- Each step makes a short list and drops it: a stop reaches it at the
-- allocator.
def Busy.alloc (n : Nat) : Nat := go (n * Busy.million) 0 where
  go : Nat → Nat → Nat
    | 0, acc => acc
    | k + 1, acc => go k ((acc + (List.replicate (k % 3 + 2) k).length) % 1000003)

-- Each step goes through `poll` and allocates nothing: a stop reaches it
-- at the poll.
def Busy.polled (n : Nat) : Nat := go (n * Busy.million) 0 where
  go : Nat → Nat → Nat
    | 0, acc => acc
    | k + 1, acc => go k (poll ((acc + k) % 1000003))

-- Neither polls nor allocates: nothing stops it before it's done. Its
-- twin defined in the REPL can be stopped: the REPL's Lean puts a
-- safepoint at the start of every function it compiles.
def Busy.spin (n : Nat) : Nat := go (n * Busy.million) 0 where
  go : Nat → Nat → Nat
    | 0, acc => acc
    | k + 1, acc => go k ((acc + k) % 1000003)

end LeanMachine
