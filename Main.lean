import LeanMachine.Host
import LeanMachine.Runs
import LeanMachine.Loop
import LeanMachine.Eval
import LeanMachine.View
import LeanMachine.Apps.Boids.Bench
import Tests.Show
import Tests.Kit
import Tests.Frames
import Tests.Boids
import Tests.Slider
import Tests.Resize
import Tests.Maximize
import Tests.Minimize
import Tests.Highlight
import Tests.Editor
import Tests.Reload

-- A desktop as a value. `World.step` and `Desktop.view` are pure (in
-- LeanMachine/); the loop here does the I/O, with `feed`
-- (LeanMachine/Loop.lean) stepping the desktop and handing what apps ask
-- to `Runs` (LeanMachine/Runs.lean), `eval` (LeanMachine/Eval.lean)
-- evaluating Lean, and `render` (LeanMachine/Host.lean) the only code
-- that draws. The tests for `--test` are moving to Tests/, with what
-- they share (Tests/Kit.lean); the rest are still below.

open LeanMachine LeanMachine.Tests

/-! ## The loop: the I/O -/

-- Applies every waiting event, the outcomes of runs that ended, a tick
-- with the time, and a frame if one is due (at `due`, in nanoseconds on
-- the monotonic clock), then draws once. `frames` stops it early (for
-- tests); the window's close button or Esc stops it any time.
partial def run (c : Canvas) (svc : Services) (d : Desktop) (runs : Runs)
    (frames : Option Nat) (due : Nat := 0) : IO Unit := do
  if frames == some 0 then runs.stopAll; return
  let mut d := d
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
    -- Esc closes the menu if it's open, and quits if it isn't.
    | some (.key .escape m) =>
      if d.now.menu.isNone then quit := true
      else (d, runs) ← feed svc d runs [.key .escape m]
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
  render c d.view
  Host.present c
  run c svc d runs (frames.map (· - 1)) due

-- One of each kind of picture, for `--test`: lines, circles, text placed in
-- boxes, and a picture moved and cut to a box.
def sampler : Picture :=
  let label (x y : Float) (s : String) : Picture := .text x y 13 0x7aa2f7 s
  let cells (x y size : Float) (n : Nat) : Picture :=
    .group ((List.range (n + 1)).map fun i =>
      let cx := x + monoAdvance size * i.toFloat
      .line cx y cx (y + 5) 1 0x565f89)
  let box (y : Float) (a : Align) (s : String) : Picture :=
    .group [.rect 40 y 260 40 6 0x414868, .rect 42 (y + 2) 256 36 5 0x1a1b26,
            .textIn 54 y 236 40 16 a 0xc0caf5 s]
  .group [
    .rect 0 0 screenW screenH 0 0x24283b,
    label 40 40 "line, 1 to 6 wide",
    .group ((List.range 6).map fun i =>
      let x := 40 + 36 * i.toFloat
      .line x 60 (x + 24) 160 (i.toFloat + 1) 0x7aa2f7),
    label 300 40 "circle and ring",
    .circle 360 110 50 0x9ece6a,
    .ring 490 110 50 4 0xe0af68,
    label 40 220 "textIn: left, center, right",
    box 236 .left "left", box 284 .center "center", box 332 .right "right",
    label 360 220 "lines at angles",
    .ring 440 320 70 2 0x565f89,
    .group ((List.range 12).map fun i =>
      let a := i.toFloat * pi / 6
      .line (440 + 52 * a.sin) (320 - 52 * a.cos)
            (440 + 66 * a.sin) (320 - 66 * a.cos) 3 0xc0caf5),
    label 620 40 "translate, then clip to the gray box",
    .translate 620 60 (.group [
      .rect 0 0 200 120 0 0x414868,
      .clip 0 0 200 120 (.group [
        .circle 200 120 70 0xf7768e,
        .textIn 0 0 200 120 40 .center 0xc0caf5 "clipped text"])]),
    -- Drawn after the translate and clip: where it is says both were undone.
    label 620 220 "after them, back where it was",
    .circle 640 250 12 0xbb9af7,
    -- Ticks at the cells' edges: each character, narrow or wide, in its own.
    label 40 440 "mono: a cell per character, a cursor after column 4",
    .mono 40 480 15 0xc0caf5 "let x := 42 -- héllo",
    cells 40 486 15 20,
    .rect (40 + monoAdvance 15 * 4) (480 - 13) 2 17 0 0xf7768e,
    .mono 40 540 24 0x9ece6a "iiiii MMMMM 01234",
    cells 40 548 24 17 ]

-- The pure world, driven by a script of events instead of a person.
def test (c : Canvas) (svc : Services) : IO Unit := do
  let grab := Event.press 300 (160 + 10)          -- Clock's title
  -- A press on the middle of item `i` of a menu at (x, y).
  let item (x y : Float) (i : Nat) : Event :=
    .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
  -- The menu opens Notes at (100, 400). Its body starts at (103, 428), so
  -- this press drops a dot at (40, 60) in its own coordinates.
  let dot := Event.press (103 + 40) (428 + 60)
  let script := [.tick ⟨10, 8, 30⟩,                 -- every app hears it
                 grab, .motion 1000 120, .release 1000 120,
                 .menu 600 450, item 600 450 0,     -- right-click, Clock
                 .motion 100 400,
                 .key (.char 'n') ctrlShift,        -- the menu here
                 item 100 400 4,                    -- Notes
                 dot,
                 -- Notes hears typing. A plain or shifted N types; only
                 -- Ctrl+Shift+N is the desktop's.
                 .text "héllo, ", .text "wörld ",
                 .key (.char 'n') {}, .text "n",
                 .key (.char 'n') { shift := true }, .text "N",
                 .key .left { ctrl := true, shift := true },
                 .press (80 + repl.size.1 + 2 * frame - 15) (70 + 14), -- REPL's close box
                 .tick ⟨10, 8, 31⟩]
  let d := script.foldl Desktop.step start
  IO.println s!"after the script: {d.now.windows.map (·.title)}, \
    focus {d.now.focus}, {d.past.length} earlier worlds, \
    menu open {d.now.menu.isSome}"
  let clockWin := d.now.windows.find? (·.title == "Clock")
  IO.println s!"Clock at {clockWin.map (·.x)} {clockWin.map (·.y)}; \
    in the start world still at {(start.now.windows.find? (·.title == "Clock")).map (·.x)}"
  render c d.view; shot c "after-script.png"
  -- The menu open, the pointer on its second item.
  let open_ := (d.step (.menu 700 250)).step
    (.motion 720 (Menu.itemY ⟨700, 250⟩ 1 + 5))
  render c open_.view; shot c "menu.png"
  let off := open_.step (.press 20 20)
  IO.println s!"a press off the menu: menu open {off.now.menu.isSome}, \
    {off.now.windows.length} windows, {off.past.length} earlier worlds"
  let undo := Event.key (.char 'z') ctrlShift
  let d := (d.step undo).step undo
  IO.println s!"after two undos: {d.now.windows.map (·.title)}"
  render c d.view; shot c "after-undo.png"
  render c sampler; shot c "sampler.png"
  -- What the decoder makes of events as the shim hands them back.
  let raw (kind a b : Float) (text := "") : RawEvent := ⟨⟨#[kind, a, b, 0]⟩, text⟩
  let shown : Option Event → String
    | some (.key k m) => k.show m
    | some (.text s) => s!"text {s.quote}"
    | some _ => "another event"
    | none => "nothing"
  let decoded := [raw 5 78 0x41, raw 5 0x40000050 0, raw 5 13 0x200,
                  raw 6 0x40 0 "n", raw 6 0 0 "é"].map (shown ∘ Event.decode)
  IO.println s!"decoded: {decoded}"
  IO.println s!"mono: the font's advance is {← c.monoEm} em, the grid's \
    {monoAdvance 1} em"
  -- The REPL, typed into and edited: first a `Repl` alone, its lines
  -- evaluated at once, then on the desktop after a press in its body
  -- (left of Clock) focuses it.
  let key (k : Key) : AppEvent := .key k {}
  let line (s : String) : List AppEvent := [.text s, key .enter]
  let typing : List AppEvent :=
    line "1 + 1" ++
    [.text "\"helo\"", key .left, key .left, .text "l",  -- "hello"
     key .home, .text "String.length ", key .enter,
     .text "xabc", key .home, key .delete, key .enter,     -- abc: unknown
     key .backspace, key .enter] ++                        -- empty: asks nothing
    (List.range 10).flatMap (fun i => line s!"{i + 1} * {i + 1}") ++
    line (String.join (List.replicate 14 "1234567890")) ++ -- wraps
    [.text "draft", key .up, key .up, key .down, key .down, -- the draft again
     key .left, key .left]
  let r ← typing.foldlM (hearNow svc) ({} : Repl)
  let entry : Entry → String
    | .note s => s!"note {s.quote}"
    | .input s _ => s!"> {s}"
    | .output s => s
    | .warning s => s!"warning {s.quote}"
    | .error s => s!"error {s.quote}"
  IO.println s!"REPL line {(String.ofList (r.line.before.reverse ++ '|' :: r.line.after)).quote}, \
    {r.history.length} lines of history, \
    transcript starts {(r.transcript.reverse.take 7).map entry}"
  let r ← [key .up, key .up, key .up].foldlM (hearNow svc) r
  IO.println s!"three Ups: {r.line.text.quote}"
  let toEvent : AppEvent → Option Event
    | .text s => some (.text s)
    | .key k m => some (.key k m)
    | _ => none
  let d ← (Event.press 120 200 :: typing.filterMap toEvent).foldlM (stepNow svc) start
  IO.println s!"focused: {(d.now.windows.find? (·.id == d.now.focus)).map (·.title)}"
  render c d.view; shot c "repl.png"

@[extern "sv_set_masking"] opaque setMasking (on : UInt8) : IO Unit
-- Is the ref emptied by `Ref.take`, and not put back? Reading it would
-- wait for ever.
@[extern "sv_ref_taken"] opaque refTaken {α : Type} (r : @& IO.Ref α) : IO Bool

-- Ten runs, each cut off 70 ms after it starts, while it does `step`
-- over and over (compiled code: the stop isn't offered to it): how many
-- left `stuck` true, and how long the stops took on average.
def cutOffMidway {σ : Type} (fresh : IO σ) (step : σ → Nat → IO Unit)
    (stuck : σ → IO Bool) : IO (Nat × Nat × List σ) := do
  let mut left := 0
  let mut total := 0
  let mut kept := []
  for _ in [0:10] do
    let x ← fresh
    let flag ← StopFlag.new
    let amb : Ambient := { world := start.now, opened := ← IO.mkRef [] }
    let task ← IO.asTask (prio := .dedicated)
      (guardedIO flag amb do for i in [0:1000000000] do step x i)
    IO.sleep 20
    flag.raise
    let t0 ← IO.monoNanosNow
    let _ ← IO.wait task
    total := total + ((← IO.monoNanosNow) - t0) / 1000000
    if ← stuck x then left := left + 1
    kept := x :: kept   -- not freed: a locked mutex mustn't be destroyed
  return (left, total / 10, kept)

-- `Ref.modify` and a mutex, cut off midway with masking off, then on.
def testMasking : IO Unit := do
  -- Most of each step is spent in the function `modify` applies, between
  -- the take and the put.
  let modifyStep (r : IO.Ref (List Nat)) (i : Nat) : IO Unit :=
    r.modify fun l => ((List.range 200).map (· + i + l.length)).take 1
  let lockStep (m : Std.BaseMutex × IO.Ref Nat) (i : Nat) : IO Unit := do
    m.1.lock
    m.2.set ((List.range 200).map (· + i)).length
    m.1.unlock
  let isLocked (m : Std.BaseMutex × IO.Ref Nat) : IO Bool := do
    if ← m.1.tryLock then m.1.unlock; return false else return true
  for masking in [false, true] do
    setMasking (if masking then 1 else 0)
    let (taken, msR, _) ← cutOffMidway (IO.mkRef []) modifyStep refTaken
    let (locked, msM, _) ← cutOffMidway (do return (← Std.BaseMutex.new, ← IO.mkRef 0))
      lockStep isLocked
    IO.println s!"masking {if masking then "on" else "off"}: Ref.modify cut off 10 times \
      left the ref taken {taken} times ({msR} ms a stop); a lock held while cut off \
      left the mutex locked {locked} times ({msM} ms)"
  setMasking 1

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

def main (args : List String) : IO Unit := do
  let c ← Canvas.new screenW.toUInt32 screenH.toUInt32
  -- The REPLs' Lean is imported in the background; the first line waits
  -- for it.
  let t0 ← IO.monoNanosNow
  let base ← startBase
  let svc : Services := { wake := Host.wake, eval := LeanMachine.eval base,
                          reload := LeanMachine.reload base, root := projectRoot }
  match args with
  | ["--test"] =>
    let _ ← IO.wait base
    IO.FS.createDirAll testOut
    IO.println s!"the REPLs' Lean imported in {((← IO.monoNanosNow) - t0) / 1000000} ms, \
      RSS {← rssMB} MB"
    test c svc; testResize c svc; testMaximize c svc; testMinimize c; testFrames c svc; testBoids c; testSlider c svc; testLean c svc; testEditor c svc; testReload c svc; testRuns c svc; testMasking
  | ["--bench"] =>
    let _ ← IO.wait base
    Boids.bench
  | ["--frames", n] =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c svc start {} n.toNat?
  | _ =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c svc start {} none
