import Tests.Kit

/-! # `--test`: runs

Lean evaluated on real threads through the desktop's REPL, stopped by
Ctrl+C, undone, two REPLs at once, a window closed under its run, and
what stops leak (docs/design/runs/README.md,
docs/design/stopping/README.md). -/

namespace LeanMachine.Tests

-- Runs on real threads, driven by a script: the desktop's REPL evaluates
-- Lean, Ctrl+C stops it, and the outcomes come back to it.
def testRuns (c : Canvas) (svc : Services) : IO Unit := do
  let feed := feed svc
  let settle := settle svc
  let ctrlC := Event.key (.char 'c') { ctrl := true }
  let enter (s : String) : List Event := [.text s, .key .enter {}]
  let ms (t0 : Nat) : IO Nat := return ((← IO.monoNanosNow) - t0) / 1000000
  -- Enters each line and waits for it, and says what came back.
  let lines (d : Desktop) (runs : Runs) (ls : List String) :
      IO (Desktop × Runs) := ls.foldlM (init := (d, runs)) fun (d, runs) l => do
    let t0 ← IO.monoNanosNow
    let (d, runs) ← feed d runs (enter l)
    let (d, runs, seen) ← settle d runs
    IO.println s!"  {l} → {seen.map (·.showDone)} ({← ms t0} ms)"
    return (d, runs)
  -- A press in the REPL's body focuses it.
  let (d, runs) ← feed start {} [.press 120 200]
  -- What the REPL asks for, as the world hands it to the loop.
  let (_, asked) := ((enter "1 + 1").foldl Desktop.step d).takeAsked
  IO.println s!"Enter asks for: {asked.map fun a => s!"{a.request.show} from window {a.win}"}"
  IO.println "lines, each waited for:"
  let (d, runs) ← lines d runs
    ["1 + 1", "def sq (n : Nat) := n * n", "sq 12", "sq \"x\"",
     "namespace Shapes", "def dot := Picture.circle 0 0 4 0xffffff", "end Shapes",
     "Shapes.dot matches .circle ..",
     "(·.windows.map (·.title)) <$> world", "clock", "(·.catalog.map (·.1)) <$> world",
     "IO.println \"printed\"",
     "#eval [1, 2, 3].map sq"]
  -- Enters a line, presses Ctrl+C 300 ms later, and says how the run
  -- ended and how long after Ctrl+C.
  let stopAt (d : Desktop) (runs : Runs) (line : String) (png : Option String := none) :
      IO (Desktop × Runs) := do
    let (d, runs) ← feed d runs (enter line)
    IO.sleep 300
    if let some file := png then render c d.view; shot c file
    let t0 ← IO.monoNanosNow
    let (d, runs) ← feed d runs [ctrlC]
    let (d, runs, seen) ← settle d runs
    IO.println s!"{line}, Ctrl+C at 300 ms: {seen.map (·.showDone)}, \
      {← ms t0} ms after Ctrl+C"
    return (d, runs)
  -- Stopped by Ctrl+C after 300 ms: compiled busy work, and loops
  -- defined here, which the interpreter runs. A stop is offered to IO
  -- code first: these are cut off 50 ms later.
  let (d, runs) ← lines d runs
    ["def churn : Nat → Nat → Nat | 0, a => a | n + 1, a => churn n ((List.replicate 3 n).length + a)",
     "def quiet : Nat → Nat → Nat | 0, a => a | n + 1, a => quiet n ((a + n) % 7)"]
  let (d, runs) ← stopAt d runs "Busy.alloc 2000" "repl-running.png"
  let mut d := d
  let mut runs := runs
  for line in ["Busy.polled 50000", "Busy.spin 400", "churn 100000000 0", "quiet 4000000 0"] do
    (d, runs) ← stopAt d runs line
  render c d.view; shot c "repl-runs.png"
  -- What the safepoints cost: the same loops compiled without them.
  IO.println "the safepoints' cost, each line waited for:"
  let raw := "set_option leanMachine.safepoints false in "
  (d, runs) ← lines d runs
    [raw ++ "def quietRaw : Nat → Nat → Nat | 0, a => a | n + 1, a => quietRaw n ((a + n) % 7)",
     "def countIO : Nat → IO Unit | 0 => pure () | n + 1 => countIO n",
     raw ++ "def countIORaw : Nat → IO Unit | 0 => pure () | n + 1 => countIORaw n",
     "quiet 2000000 0", "quietRaw 2000000 0", "countIO 2000000", "countIORaw 2000000"]
  -- Stops that Lean code sees: `finally` runs. Not when the stop finds
  -- pure code, nor when code catches it and goes on (it's cut off 500 ms
  -- later). A sleep ends at a stop; a loop without safepoints doesn't.
  -- Lean's elaborator sees its cancel token (`#reduce`).
  IO.println "stops that Lean sees, or doesn't:"
  (d, runs) ← lines d runs
    ["def ticks : Nat → IO Unit | 0 => pure () | n + 1 => do IO.println s!\"tick {n}\"; IO.sleep 100; ticks n",
     "partial def stubborn : IO Unit := do (do try ticks 1000 catch _ => IO.println \"caught it\"); stubborn"]
  for line in ["do try ticks 1000 finally IO.println \"cleaned up\"",
               "do try IO.println (quiet 40000000 0) finally IO.println \"cleaned up\"",
               "stubborn", "IO.sleep 100000", "quietRaw 2000000 0",
               "set_option maxRecDepth 100000 in #reduce (List.range 30000).foldl (· + ·) 0"] do
    (d, runs) ← stopAt d runs line
  render c d.view; shot c "repl-interrupt.png"
  -- An app made here opens in a window by the REPL, and runs there: a
  -- press drops a dot.
  (d, runs) ← lines d runs
    ["launch (App.of \"Dots\" ([] : List (Float × Float)) \
       (fun s e => match e with | .press x y => some ((x, y) :: s) | _ => none) \
       fun s _ _ => .group (s.map fun (x, y) => .circle x y 6 0xe0af68))"]
  (d, runs) ← feed d runs [.press (123 + 60) (138 + 50), .press (123 + 120) (138 + 90)]
  IO.println s!"windows: {d.now.windows.map (·.title)}, focus on \
    {(d.now.windows.find? (·.id == d.now.focus)).map (·.title)}"
  render c d.view; shot c "repl-launch.png"
  -- Undo takes a definition back: the REPL's Lean is in its state. Dots
  -- covers the REPL's left side now; a press on its right focuses it.
  let toRepl := Event.press 600 250
  (d, runs) ← feed d runs [toRepl]
  (d, runs) ← lines d runs ["def answer := 42"]
  (d, runs) ← feed d runs [toRepl]   -- a press: undo returns here
  (d, runs) ← lines d runs ["def more := answer + 1", "more"]
  (d, runs) ← feed d runs [.key (.char 'z') ctrlShift]
  IO.println "after undo:"
  (d, runs) ← lines d runs ["more", "answer"]
  render c d.view; shot c "repl-undo.png"
  -- Undo brings back a REPL waiting for a run whose outcome came to a
  -- world that's gone. Ctrl+C is answered at once.
  (d, runs) ← feed d runs (enter "Busy.alloc 1")
  (d, runs) ← feed d runs [toRepl]
  let (d', runs', _) ← settle d runs
  (d, runs) ← feed d' runs' [.key (.char 'z') ctrlShift]
  let (d', asked) := (d.step ctrlC).takeAsked
  let mut answers := []
  for a in asked do
    let (rs, more) ← runs.handle svc d'.now a
    runs := rs; answers := answers ++ more
  IO.println s!"after undo, Ctrl+C asks {asked.map (·.request.show)} with \
    {runs.live.length} runs going; answered at once: {answers.map (·.showDone)}"
  (d, runs) ← feed d' runs answers
  -- A run of a pure function, which no app asks for yet: its outcome goes
  -- to window 1, whose REPL isn't waiting for it.
  let (rs, _) ← runs.handle svc d.now ⟨1, .run 99 fun _ => toString (Busy.alloc 1)⟩
  let (d', runs', seen) ← settle d rs
  d := d'; runs := runs'
  IO.println s!"a pure run: {seen.map (·.showDone)}"
  -- Two REPLs evaluating at once: a second from the menu, then the first.
  let menuItem (i : Nat) : Event := .press (600 + 20) (Menu.itemY ⟨600, 450⟩ i + itemH / 2)
  (d, runs) ← feed d runs ([.menu 600 450, menuItem 1] ++ enter "Busy.alloc 30" ++
                           [toRepl] ++ enter "Busy.alloc 30")
  let t0 ← IO.monoNanosNow
  let (d', runs', seen) ← settle d runs
  d := d'; runs := runs'
  IO.println s!"two REPLs at once: {seen.map (·.showDone)} in {← ms t0} ms"
  -- A frame, drawn while a run allocates as fast as it can, and without.
  let frameUs (d : Desktop) : IO Nat := do
    let t0 ← IO.monoNanosNow
    for _ in [0:20] do render c d.view
    return ((← IO.monoNanosNow) - t0) / 20000
  let quiet ← frameUs d
  (d, runs) ← feed d runs (enter "Busy.alloc 5000")
  IO.sleep 50
  let busy ← frameUs d
  IO.println s!"a frame: {quiet} µs, {busy} µs with a run going"
  -- Closing the window stops its run: the loop sees its window is gone.
  let task? := runs.live.head?.map (·.task)
  (d, runs) ← feed d runs [.press (80 + repl.size.1 + 2 * frame - 15) (70 + 14)]
  runs ← runs.keepFor (d.now.windows.map (·.id))
  if let some task := task? then
    let t0 ← IO.monoNanosNow
    let r ← IO.wait task
    let how := match r with
      | .ok (none, _) => "stopped"
      | .ok (some _, _) => "finished"
      | .error e => toString e
    IO.println s!"closing the REPL: its run {how} {← ms t0} ms later, \
      {runs.live.length} runs going"
  -- What stops leak: 50 evaluations stopped as they allocate.
  let rss1 ← rssMB
  (d, runs) ← feed start runs [.press 120 200]
  for _ in [0:50] do
    (d, runs) ← feed d runs (enter "Busy.alloc 1000")
    IO.sleep 50
    (d, runs) ← feed d runs [ctrlC]
    let (d', runs', _) ← settle d runs
    d := d'; runs := runs'
  IO.println s!"RSS: {rss1} MB after the runs above, {← rssMB} MB after 50 more stopped"

end LeanMachine.Tests
