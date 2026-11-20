import LeanMachine.Host
import LeanMachine.Runs
import LeanMachine.Loop
import LeanMachine.Eval
import LeanMachine.View
import LeanMachine.Apps.Boids.Bench
import Tests

-- A desktop as a value. `World.step` and `Desktop.view` are pure (in
-- LeanMachine/); the loop here does the I/O, with `feed`
-- (LeanMachine/Loop.lean) stepping the desktop and handing what apps ask
-- to `Runs` (LeanMachine/Runs.lean), `eval` (LeanMachine/Eval/Repl.lean)
-- evaluating Lean, and `render` (LeanMachine/Host.lean) the only code
-- that draws. The tests for `--test` are in Tests/, and Tests.lean runs
-- them all (`Tests.all`).

open LeanMachine

/-! ## The loop: the I/O -/

-- Applies every waiting event, the outcomes of runs that ended, a tick
-- with the time, and a frame if one is due (at `due`, in nanoseconds on
-- the monotonic clock), then draws once, on a new canvas if the window
-- was resized. `frames` stops it early (for tests); the window's close
-- button or Esc stops it any time.
partial def run (c : Canvas) (svc : Services) (d : Desktop) (runs : Runs)
    (frames : Option Nat) (due : Nat := 0) : IO Unit := do
  if frames == some 0 then runs.stopAll; return
  let mut c := c
  let mut d := d
  let screen := d.now.screen
  let mut runs := runs
  let mut quit := false
  -- Waits for an event, but not past 100 ms or the start of the next
  -- second, so a clock turns over on time, and while an app animates, not
  -- past the next frame. A run that ends wakes it.
  let (_, msLeft) ← localTime
  let toFrame := (due - (← IO.monoNanosNow) + 999999) / 1000000
  let wait := min (msLeft + 1) (if d.now.animating then toFrame else 100)
  let mut raw ← Host.event wait.toUInt32
  while raw.nums.get! 0 != 0 do
    match Event.decode raw with
    | some .quit => quit := true
    -- F11 puts the window in full screen, or takes it out; the world
    -- hears the new size.
    | some (.key .f11 _) => Host.setFullscreen !(← Host.fullscreen)
    -- Esc closes the menu if it's open, takes the window out of full
    -- screen if it's in it, and quits if neither.
    | some (.key .escape m) =>
      if d.now.menu.isSome then (d, runs) ← feed svc d runs [.key .escape m]
      else if (← Host.fullscreen) then Host.setFullscreen false
      else quit := true
    -- A paste key: the focused app hears what's on the clipboard, if
    -- there's text on it, and not the key.
    | some (.key k m) =>
      if pasteKey k m then
        let s ← Host.clipboard
        unless s.isEmpty do (d, runs) ← feed svc d runs [.paste s]
      else (d, runs) ← feed svc d runs [.key k m]
    -- The middle button: the window under the pointer hears the primary
    -- selection's text, pasted where the click lands.
    | some (.middle x y) =>
      let s ← Host.primarySelection
      unless s.isEmpty do (d, runs) ← feed svc d runs [.pasteAt x y s]
    | some e => (d, runs) ← feed svc d runs [e]
    | none => pure ()
    raw ← Host.event 0
  if quit then runs.stopAll; return
  -- Runs that ended tell their windows how. Runs whose window is gone
  -- are stopped.
  let (rs, ended) ← runs.collect
  (d, runs) ← feed svc d rs ended
  runs ← runs.keepFor (d.now.windows.map (·.id))
  let (t, _) ← localTime
  (d, runs) ← feed svc d runs [.tick t]
  -- The apps that animate hear a frame, if one is due.
  let now ← IO.monoNanosNow
  let mut due := due
  if d.now.animating && now ≥ due then
    (d, runs) ← feed svc d runs [.frame (now / 1000000)]
    due := nextFrameAfter due now
  -- The canvas is the size of the world's screen, which the window's
  -- size changes (`Event.screen`).
  if d.now.screen != screen then
    c ← Canvas.new d.now.screen.w.toUInt32 d.now.screen.h.toUInt32
  render c d.view
  Host.present c
  run c svc d runs (frames.map (· - 1)) due

def main (args : List String) : IO Unit := do
  -- The canvas and the window are the size of the start's screen, and
  -- the window can be resized down to `Screen.least`.
  let screen := start.now.screen
  let least := Screen.least
  let c ← Canvas.new screen.w.toUInt32 screen.h.toUInt32
  -- The REPLs' Lean is imported in the background; the first line waits
  -- for it.
  let t0 ← IO.monoNanosNow
  let base ← startBase
  let svc : Services := { wake := Host.wake, eval := LeanMachine.eval base,
                          copy := Host.setClipboard,
                          reload := LeanMachine.reload base, root := projectRoot }
  match args with
  | ["--test"] =>
    let _ ← IO.wait base
    IO.println s!"the REPLs' Lean imported in {((← IO.monoNanosNow) - t0) / 1000000} ms, \
      RSS {← Tests.rssMB} MB"
    Tests.all c svc
  | ["--bench"] =>
    let _ ← IO.wait base
    Boids.bench
  | ["--frames", n] =>
    Host.open "Lean Machine" screen.w.toUInt32 screen.h.toUInt32
      least.w.toUInt32 least.h.toUInt32
    run c svc start {} n.toNat?
  | _ =>
    Host.open "Lean Machine" screen.w.toUInt32 screen.h.toUInt32
      least.w.toUInt32 least.h.toUInt32
    run c svc start {} none
