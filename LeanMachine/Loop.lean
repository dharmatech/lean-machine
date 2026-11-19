import LeanMachine.Runs
import LeanMachine.Desktop

/-! # The loop's parts that don't draw

`feed` steps the desktop through events and does what its apps ask,
through `Runs`; `nextFrameAfter` says when the next frame is due. `run`,
the loop itself, is in Main.lean: it waits for events, calls these, and
draws. The tests for `--test` drive the desktop with `feed` too. -/

namespace LeanMachine

-- Steps the desktop through `es`, and does what its apps ask as they ask
-- it, with what the loop lends runs. A request answered at once (a stop
-- with no run to stop) is stepped through after the rest.
partial def feed (svc : Services) (d : Desktop) (runs : Runs) :
    List Event → IO (Desktop × Runs)
  | [] => return (d, runs)
  | e :: rest => do
    let (d, asked) := (d.step e).takeAsked
    let mut runs := runs
    let mut answers := []
    for a in asked do
      let (rs, more) ← runs.handle svc d.now a
      runs := rs
      answers := answers ++ more
    feed svc d runs (rest ++ answers)

-- How far apart frames are while an app animates, in nanoseconds: 60 a
-- second.
def framePeriod : Nat := 1000000000 / 60

-- When the next frame is due, after one due at `due` and drawn at `now`:
-- a period after `due`, so that frames keep time, unless the loop fell a
-- whole period behind; then a period from `now`, so that the frames it
-- missed aren't drawn all at once.
def nextFrameAfter (due now : Nat) : Nat :=
  if now < due + framePeriod then due + framePeriod else now + framePeriod

#guard nextFrameAfter 0 5000000000 == 5000000000 + framePeriod  -- the first in a while
#guard nextFrameAfter 1000 2001000 == 1000 + framePeriod         -- 2 ms late, on time
#guard nextFrameAfter 1000 50001000 == 50001000 + framePeriod    -- 50 ms late

end LeanMachine
