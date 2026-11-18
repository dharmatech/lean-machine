import LeanMachine.Host
import LeanMachine.Runs
import LeanMachine.Eval
import LeanMachine.View
import LeanMachine.Apps.Boids.Flock

-- A desktop as a value. `World.step` and `Desktop.view` are pure (in
-- LeanMachine/); the loop here does the I/O, with `Runs`
-- (LeanMachine/Runs.lean) doing what apps ask and `eval`
-- (LeanMachine/Eval.lean) evaluating Lean, and `render`
-- (LeanMachine/Host.lean) is the only code that draws.

open LeanMachine

/-! ## The loop: the I/O -/

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

-- Waits for every run to end, up to `ms`, and tells the desktop how each
-- did; also returns the outcomes, oldest first.
partial def settle (svc : Services) (d : Desktop) (runs : Runs) (ms : Nat := 30000)
    (seen : List Event := []) : IO (Desktop × Runs × List Event) := do
  let (runs, ended) ← runs.collect
  let (d, runs) ← feed svc d runs ended
  let seen := seen ++ ended
  if runs.live.isEmpty || ms == 0 then return (d, runs, seen)
  IO.sleep 1
  settle svc d runs (ms - 1) seen

-- An app's state after `e`, with what it asks for worked out at once, on
-- this thread, outside any run.
def answerNow {σ : Type} (svc : Services) (step : σ → AppEvent → Option (σ × List Request))
    (r : σ) (e : AppEvent) : IO σ := do
  match step r e with
  | none => return r
  | some (r, asks) => asks.foldlM (init := r) fun r a => do
    let answer : AppEvent ← match a with
      | .run tag work => pure (.done tag (.value (work ())) 0)
      | .eval tag src env => do
        pure (.done tag (← svc.eval src env (← IO.CancelToken.new)) 0)
      | .stop tag => pure (.done tag (.stopped [] false) 0)
      | .read tag _ | .write tag _ _ | .list tag _ => do
        pure (.done tag (← (fileOutcome svc.root a).getD (pure (.failed "?"))) 0)
      -- The apps it made go nowhere: there's no world here.
      | .reload tag path src => do
        pure (.done tag (← svc.reload path src (← IO.CancelToken.new)).1 0)
    return ((step r answer).map (·.1)).getD r

def hearNow (svc : Services) : Repl → AppEvent → IO Repl := answerNow svc Repl.step

-- The desktop after `e`, with the runs its apps ask for ended.
def stepNow (svc : Services) (d : Desktop) (e : Event) : IO Desktop := do
  let (d, runs) ← feed svc d {} [e]
  let (d, _, _) ← settle svc d runs
  return d

-- Where `--test` puts what it makes, the pictures and the editor's
-- scratch file, wherever it runs from. It's under .lake, which git
-- ignores, and can be deleted at any time.
def testOut : System.FilePath := projectRoot / ".lake" / "test"

-- The canvas as a picture in `testOut`.
def shot (c : Canvas) (name : String) : IO Unit := c.savePng (testOut / name).toString

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

def LeanMachine.Request.show : Request → String
  | .run tag _ => s!"run {tag}"
  | .eval tag src _ => s!"eval {tag} {src.quote}"
  | .stop tag => s!"stop {tag}"
  | .read tag path => s!"read {tag} {path}"
  | .write tag path _ => s!"write {tag} {path}"
  | .list tag dir => s!"list {tag} {dir}"
  | .reload tag path _ => s!"reload {tag} {path}"

def LeanMachine.Said.show : Said → String
  | .info s => s
  | .warning s => s!"warning: {s}"
  | .error s => s!"error: {s}"

def LeanMachine.Outcome.show : Outcome → String
  | .value s => s!"value {s}"
  | .evaluated said _ => s!"said {said.map Said.show}"
  | .stopped said cleanly =>
    s!"stopped{if cleanly then " cleanly" else ""}\
      {if said.isEmpty then "" else s!", said {said.map Said.show}"}"
  | .failed why => s!"failed: {why}"
  | .read s => s!"read {s.length} characters"
  | .wrote => "wrote"
  | .listed paths => s!"listed {paths.length} files"
  | .reloaded said _ apps =>
    s!"reloaded {apps}, said {said.map fun (r : Remark) => s!"{r.line + 1}:{r.col + 1} {r.said.show}"}"

def LeanMachine.Event.showDone : Event → String
  | .done win tag o ms => s!"window {win} run {tag}: {o.show}, {ms} ms"
  | .launch win app => s!"window {win} opened {app.title}"
  | .reload win apps => s!"window {win} reloaded {apps.map (·.1)}"
  | _ => "another event"

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

def rssMB : IO Nat := do
  let s ← IO.FS.readFile "/proc/self/status"
  let line := ((s.splitOn "\n").find? (·.startsWith "VmRSS:")).getD ""
  let kb := ((line.drop 6).trimAscii.toString.takeWhile Char.isDigit).toNat!
  return kb / 1024

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

def LeanMachine.TokenKind.show : TokenKind → String
  | .keyword => "keyword" | .symbol => "symbol" | .constant => "constant"
  | .ident => "ident" | .number => "number" | .string => "string"
  | .comment => "comment" | .error => "error"

-- `s` cut into its tokens, each with its kind: `def:keyword`.
def showTokens (s : String) (ts : Array Token) : String :=
  " ".intercalate (ts.toList.map fun t =>
    s!"{String.ofList ((s.toList.drop t.start).take (t.stop - t.start))}:{t.kind.show}")

-- How many `mono`s a picture draws: a row of a REPL is one per run.
partial def LeanMachine.Picture.monos : Picture → Nat
  | .mono .. => 1
  | .group ps => ps.foldl (· + ·.monos) 0
  | .translate _ _ p | .clip _ _ _ _ p => p.monos
  | _ => 0

-- Microseconds a call of `act`, over `n` calls. `act` gets the call's
-- number, so that the work in it can't be done once for all.
def usPer (n : Nat) (act : Nat → IO Unit) : IO Float := do
  let t0 ← IO.monoNanosNow
  for i in [0:n] do act i
  return ((← IO.monoNanosNow) - t0).toFloat / n.toFloat / 1000

-- Highlighting and completion: the tokens the REPL's Lean reads in a
-- line, what Tab makes of names with one completion and with several,
-- and what each costs.
def testLean (c : Canvas) (svc : Services) : IO Unit := do
  let entered := ["def sq (n : Nat) : Nat := n * n  -- squares",
                  "def squares := [1, 2, 3].map sq",
                  "#eval (sq 12, 'x', 2.5, \"twelve\", `Nat.succ, squares)",
                  "IO.println \"unterminated"]
  let editing := "List.map sq [1, 2, 3] |>.foldl (· + ·) 0 /- sum -/ ¿"
  -- A REPL alone: its Lean comes when it first hears a tick.
  let r ← hearNow svc {} (.tick ⟨10, 8, 30⟩)
  let some env := r.env | throw (IO.userError "the REPL didn't get its Lean")
  IO.println "tokens, as the REPL's Lean reads them:"
  for l in entered.take 1 ++ [editing] do
    IO.println s!"  {showTokens l (env.tokens l)}"
  let ctrlC : AppEvent := .key (.char 'c') { ctrl := true }
  let r ← (entered.flatMap fun l => [.text l, .key .enter {}]).foldlM (hearNow svc) r
  IO.println s!"  after the def: {showTokens "sq squares" ((r.env.getD env).tokens "sq squares")}"
  -- Tab after a name typed on a cleared line.
  IO.println "Tab completes:"
  for word in ["Busy.al", "monoAdv", "sq", "Picture.", "List.ma", "names", "zzq", "\"Nat.su"] do
    let r ← [ctrlC, .text word, .key .tab {}].foldlM (hearNow svc) r
    let offered := match r.offer with
      | some o => s!"{o.names.length} offered{if o.names.isEmpty then "" else s!": {o.names.take 12}"}"
      | none => "nothing offered"
    IO.println s!"  {word.quote} → {r.line.text.quote}, {offered}"
  -- On the desktop: the same lines, the line being edited, then Tab.
  let key (k : Key) : Event := .key k {}
  let d ← ([Event.press 120 200] ++
    entered.flatMap (fun l => [Event.text l, key .enter]) ++ [Event.text editing]).foldlM (stepNow svc) start
  render c d.view; shot c "repl-highlight.png"
  let d ← [.key (.char 'c') { ctrl := true }, .text "Picture.", key .tab].foldlM (stepNow svc) d
  render c d.view; shot c "repl-complete.png"
  let d ← [.key (.char 'c') { ctrl := true }, .text "List.ma", key .tab].foldlM (stepNow svc) d
  render c d.view; shot c "repl-complete-many.png"
  -- What it costs. A keystroke: the REPL steps, and its Lean reads the
  -- line again.
  let env := r.env.getD env
  let h := env.state.held
  IO.println "costs:"
  let lexUs ← usPer 2000 fun i => do
    if (env.tokens (editing.push (Char.ofNat (97 + i % 26)))).isEmpty then IO.println "?"
  -- Four times the line, with no error to stop the tokenizer early.
  let longLine := " ".intercalate (List.replicate 4 (editing.dropEnd 2).toString)
  let lexLongUs ← usPer 1000 fun i => do
    if (env.tokens (longLine.push (Char.ofNat (97 + i % 26)))).isEmpty then IO.println "?"
  let typed := ({ r with line := .ofString editing } : Repl).relex
  let keyUs ← usPer 2000 fun i => do
    if let some (r', _) := typed.step (.text (Char.ofNat (97 + i % 26)).toString) then
      if r'.tokens.isEmpty then IO.println "?"
  let parseUs ← usPer 2000 fun i => do
    if let .ok stx := Lean.Parser.runParserCategory h.cmd.env `term
        (editing.dropEnd 1 |>.toString |>.push (Char.ofNat (97 + i % 26))) then
      if stx.getNumArgs == 1000 then IO.println "?"
  IO.println s!"  tokens of a line of {editing.length} characters: {lexUs} µs; of \
    {longLine.length}: {lexLongUs} µs; a keystroke in the REPL (step and tokens): \
    {keyUs} µs; Lean's parser on the line, for comparison: {parseUs} µs"
  for word in ["Busy.al", "s", "List.ma", "Nat."] do
    let n := (env.complete word).size
    let us ← usPer 200 fun i => do
      if (env.complete (if i == 1000 then "" else word)).size == 1000000 then IO.println "?"
    IO.println s!"  Tab on {word.quote}: {n} names, {us} µs"
  let t0 ← IO.monoNanosNow
  let index := nameIndex h.cmd.env
  let names := index.fold (fun n _ l => n + l.length) 0
  IO.println s!"  the name index: {names} names in {index.size} namespaces, made in \
    {((← IO.monoNanosNow) - t0) / 1000000} ms, of {h.cmd.env.constants.map₁.size} constants imported"
  -- A REPL full of highlighted lines, drawn, against the same lines in
  -- one colour each.
  let full : Repl := { typed with transcript :=
    (List.replicate 15 (Entry.input editing (env.tokens editing))) ++ r.transcript }
  let plain : Repl := { full with tokens := #[], transcript := full.transcript.map fun
    | .input s _ => .input s #[] | e => e }
  for (name, repl) in [("highlighted", full), ("one colour", plain)] do
    let pic := repl.view 554 269
    let viewUs ← usPer 200 fun i => do
      if (repl.view (554 + (i % 2).toFloat) 269).monos == 0 then IO.println "?"
    let us ← usPer 200 fun i => do
      render c (repl.view (554 + (i % 2).toFloat) 269)
    IO.println s!"  a REPL window {name}: {pic.monos} monos; the view in {viewUs} µs, \
      the view drawn in {us} µs"

def LeanMachine.Carry.show : Carry → String
  | .code => "code" | .comment d => s!"comment {d}" | .string => "string"

-- A line of the editor's file, in short: where it starts, its tokens'
-- kinds, and where the next starts.
def showLexed (l : Lexed) : String :=
  let kinds := l.tokens.toList.map (·.kind.show)
  let kinds := kinds.foldr (init := []) fun k ks => if ks.head? == some k then ks else k :: ks
  s!"{l.text.quote}: [{l.carryIn.show}] {" ".intercalate kinds} [→ {l.carry.show}]"

def showFile (e : Editor) : IO Unit := do
  let b := e.buffer
  for l in b.above.reverse ++ b.current :: b.below do
    IO.println s!"    {showLexed l}"

-- The editor: lines read with what the line before left open, an editor
-- alone on a scratch file (opening, comments across lines, Enter, joins,
-- saving, leaving), then on the desktop with Clock.lean, and costs.
def testEditor (c : Canvas) (svc : Services) : IO Unit := do
  let r ← hearNow svc {} (.tick ⟨10, 8, 30⟩)
  let some env := r.env | throw (IO.userError "the REPL didn't get its Lean")
  IO.println "tokens of a file's lines, each starting where the one before left off:"
  let file := ["def x := 1 /- a comment", "  that /- nests -/ and", "  ends -/ def y := \"a string",
               "that ends\" ++ \"here\"", "/-- A doc comment", "-/ theorem t : True := trivial"]
  let _ ← file.foldlM (init := Carry.code) fun c l => do
    let (ts, c') := env.tokensFrom c l
    IO.println s!"  [{c.show}] {showTokens l ts} [→ {c'.show}]"
    return c'
  -- The editor alone, its requests answered at once.
  let key (k : Key) : AppEvent := .key k {}
  let ctrl (ch : Char) : AppEvent := .key (.char ch) { ctrl := true }
  let ed (e : Editor) (evs : List AppEvent) : IO Editor := evs.foldlM (answerNow svc Editor.heard) e
  let dir := testOut / "editor"
  IO.FS.createDirAll dir
  IO.FS.writeFile (dir / "Scratch.lean") "def a := 1\ndef b := 2\ndef c := 3\n"
  let path := ".lake/test/editor/Scratch.lean"
  let e ← ed {} [.tick ⟨10, 8, 30⟩]
  IO.println s!"the editor asks for its Lean ({e.env.isSome}) and the files: \
    {e.files.size} Lean files, {e.files.toList.take 4}…"
  -- Scratch.lean is in a hidden folder, so it isn't listed: the test lists it.
  let e ← ed { e with files := #[path] } [key .enter]
  IO.println s!"opened {e.title}: {e.buffer.count} lines, {e.note.quote}"
  let e ← ed e [.text "/- "]
  IO.println s!"  \"/- \" typed at the start: {e.title}"
  showFile e
  let e ← ed e [key .down, key .down, key .«end», .text " -/"]
  IO.println "  \" -/\" at the end of the third line:"
  showFile e
  let e ← ed e [key .down, .text "def d :=", key .enter, .text "4", key .enter, key .backspace,
    key .backspace, key .backspace, .text " -- the end"]
  IO.println s!"  Enter after `:=`, then Enter and Backspaces: cursor at {e.buffer.row + 1}:{e.buffer.col + 1}"
  showFile e
  let e ← ed e [ctrl 's']
  let disk ← IO.FS.readFile (dir / "Scratch.lean")
  IO.println s!"  Ctrl+S: {e.title}, {e.note.quote}; on disk: {disk.quote}; \
    left beside it: {← (dir / "Scratch.lean.saving").pathExists}"
  let e ← ed e [key .home, key .backspace, ctrl 'o']
  IO.println s!"  a change, then Ctrl+O: {e.title}, {e.note.quote}"
  let e ← ed e [ctrl 'o']
  IO.println s!"  Ctrl+O again: {e.title}, path {e.path}, {e.files.size} files listed again"
  -- On the desktop: Editor from the menu, then Clock.lean, found by typing.
  let item (x y : Float) (i : Nat) : Event := .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
  let d ← [Event.menu 300 100, item 300 100 2].foldlM (stepNow svc) start
  let title (d : Desktop) := (d.now.windows.find? (·.id == d.now.focus)).map (·.title)
  IO.println s!"from the menu: {title d}"
  render c d.view; shot c "editor-files.png"
  let dkey (k : Key) : Event := .key k {}
  let d ← [Event.text "apps/cl", dkey .enter].foldlM (stepNow svc) d
  IO.println s!"\"apps/cl\", Enter: {title d}"
  -- Line 16 is `def clockFace …`; a new line in it, and Tab.
  let d ← ((List.replicate 16 (dkey .down)) ++ [dkey .«end», dkey .enter, .text "toward.",
    dkey .backspace, .text " + TimeOfDay.", dkey .tab]).foldlM (stepNow svc) d
  IO.println s!"Tab after `TimeOfDay.`: {title d}"
  render c d.view; shot c "editor-complete.png"
  -- A comment opened at the top runs to the end of the file; the wheel
  -- scrolls down to show it.
  let d ← [Event.key .home { ctrl := true }, .text "/- ", .wheel 600 300 (-3)].foldlM (stepNow svc) d
  render c d.view; shot c "editor-comment.png"
  -- The editor alone again: a press places the cursor, the wheel scrolls.
  let e ← ed e [.text "apps/ed", key .enter]
  let e ← ed e [.press (Editor.textX + monoAdvance edFont * 6 + 2) (edPad + 5)]
  IO.println s!"{e.title}: a press by the left edge of row 1, column 7: cursor at \
    {e.buffer.row + 1}:{e.buffer.col + 1}"
  let e ← ed e [.wheel 100 100 (-2), .wheel 100 100 (-0.2), .wheel 100 100 (-0.2)]
  IO.println s!"  the wheel down 2 steps, then two fifths: top line {e.top + 1}, cursor still at {e.buffer.row + 1}"
  -- Costs, on Repl.lean.
  IO.println "costs:"
  let text ← IO.FS.readFile (projectRoot / "LeanMachine/Apps/Repl.lean")
  let b := Buffer.ofText text
  let lexAllUs ← usPer 20 fun i => do
    if (Buffer.lexAll env (if i == 1000 then {} else b)).count == 0 then IO.println "?"
  let opened := Editor.opened { base := some env, env := some env } "Repl.lean" text 0
  let middle := { opened with buffer := opened.buffer.goTo 120 4 }.follow
  let keyUs ← usPer 2000 fun i => do
    if let some (e', _) := middle.heard (.text (Char.ofNat (97 + i % 26)).toString) then
      if e'.buffer.here.tokens.isEmpty then IO.println "?"
  let atTop := { opened with buffer := opened.buffer.goTo 0 0 }
  let commentUs ← usPer 20 fun i => do
    if let some (e', _) := atTop.heard (.text (if i == 1000 then "x" else "/-")) then
      if e'.buffer.below.getLast?.map (·.carry) == some .code then IO.println "?"
  let commented := { atTop with buffer := Buffer.relex env { atTop.buffer with
    line := atTop.buffer.line.insert "/-" |>.toStart } }
  let uncommentUs ← usPer 20 fun i => do
    if let some (e', _) := commented.heard (.key (if i == 1000 then .left else .delete) {}) then
      if e'.buffer.below.getLast?.map (·.carry) != some .code then IO.println "?"
  let downUs ← usPer 2000 fun i => do
    if let some (e', _) := middle.heard (.key (if i == 100000 then .up else .down) {}) then
      if e'.buffer.row == 0 then IO.println "?"
  IO.println s!"  Repl.lean, {b.count} lines: read every line {lexAllUs} µs; a keystroke on \
    line 121 (step and tokens) {keyUs} µs; \"/-\" typed at the top, every line below read \
    again {commentUs} µs; that \"/\" deleted, every line read again {uncommentUs} µs; \
    Down {downUs} µs"
  let pic := middle.view editorSize.1 editorSize.2
  let viewUs ← usPer 200 fun i => do
    if (middle.view (editorSize.1 + (i % 2).toFloat) editorSize.2).monos == 0 then IO.println "?"
  let drawUs ← usPer 200 fun i => do
    render c (middle.view (editorSize.1 + (i % 2).toFloat) editorSize.2)
  let frameUs ← usPer 50 fun _ => render c d.view
  IO.println s!"  an editor full of code: {pic.monos} monos; the view in {viewUs} µs, drawn in \
    {drawUs} µs; the desktop with it drawn in {frameUs} µs"

-- The texts a picture shows, in order.
partial def LeanMachine.Picture.texts : Picture → List String
  | .text _ _ _ _ s | .textIn _ _ _ _ _ _ _ s | .mono _ _ _ _ s => [s]
  | .group ps => ps.flatMap (·.texts)
  | .translate _ _ p | .clip _ _ _ _ p => p.texts
  | _ => []

-- An app after `e`, with what it asks for worked out at once, on this
-- thread. The apps a reload makes go nowhere: there's no world here.
def appNow (svc : Services) (a : App) (e : AppEvent) : IO App :=
  answerNow svc (fun (a : App) e => a.step e) a e

def LeanMachine.Win.texts (w : Win) : List String := (w.app.view w.bodyW w.bodyH).texts

-- A small app in a file of its own, which the menu doesn't have.
def helloSrc : String := "import LeanMachine.App

namespace LeanMachine

def hello : App :=
  App.of \"Hello\" (0 : Nat) (fun n e => match e with | .press .. => some (n + 1) | _ => none)
    (fun n w h => .textIn 0 0 w h 20 .center 0x9ece6a s!\"hello, {n} presses\") (size := (300, 120))

end LeanMachine
"

-- Reloading apps from their files: each app's file in the desktop's
-- Lean, files that can't be reloaded, an editor alone, then the desktop
-- with real runs: Clock.lean edited and reloaded into the open clock,
-- undone, an error, Editor.lean reloaded from an editor, a stop, a new
-- app; then what reloaded code costs to run, and memory over many
-- reloads.
def testReload (c : Canvas) (svc : Services) : IO Unit := do
  let ms (t0 : Nat) : IO Nat := return ((← IO.monoNanosNow) - t0) / 1000000
  let reloadNow (path src : String) : IO (Outcome × List (Lean.Name × App) × Nat) := do
    let t0 ← IO.monoNanosNow
    let (o, apps) ← svc.reload path src (← IO.CancelToken.new)
    return (o, apps, ← ms t0)
  IO.println "each app's file, reloaded in the desktop's Lean three times:"
  let mut made : List (Lean.Name × App) := []
  for file in ["Clock", "Placeholder", "Repl", "Editor"] do
    let path := s!"LeanMachine/Apps/{file}.lean"
    let src ← IO.FS.readFile (projectRoot / path)
    let mut times := #[]
    let mut said := ""
    let mut apps := []
    for _ in [0:3] do
      let (o, a, t) ← reloadNow path src
      times := times.push t; said := o.show; apps := a
    made := made ++ apps
    IO.println s!"  {file}.lean: {times} ms; {said}"
  let madeApp (n : Lean.Name) : App := ((made.find? (·.1 == n)).map (·.2)).getD default
  IO.println "files it can't reload:"
  for path in ["LeanMachine/Desktop.lean", "Main.lean"] do
    let (o, _, _) ← reloadNow path (← IO.FS.readFile (projectRoot / path))
    IO.println s!"  {path}: {o.show}"
  let clockSrc ← IO.FS.readFile (projectRoot / "LeanMachine/Apps/Clock.lean")
  let (o, apps, _) ← reloadNow "Clock.lean" (clockSrc.replace "t.digits]" "t.digit]")
  IO.println s!"  Clock.lean with `t.digit`: {o.show}; {apps.length} apps"
  -- An editor alone, its requests answered at once.
  let key (k : Key) : AppEvent := .key k {}
  let ctrl (ch : Char) : AppEvent := .key (.char ch) { ctrl := true }
  let ed (e : Editor) (evs : List AppEvent) : IO Editor := evs.foldlM (answerNow svc Editor.heard) e
  let fileOf (e : Editor) : List Lexed := e.buffer.above.reverse ++ e.buffer.current :: e.buffer.below
  let lineWith (e : Editor) (s : String) : String :=
    ((fileOf e).find? (·.text.startsWith s)).map showLexed |>.getD "?"
  let marked (e : Editor) : List String := (fileOf e).zipIdx.filterMap fun (l, i) =>
    if l.said.isEmpty then none else some s!"line {i + 1}: {l.said.map (·.2.show)}"
  let e ← ed {} [.tick ⟨10, 8, 30⟩, .text "apps/cl", key .enter]
  IO.println s!"an editor alone, on {e.title}: {lineWith e "    clockFace"}"
  let e ← ed e [ctrl 'r']
  IO.println s!"  Ctrl+R: {e.note.quote}, now {lineWith e "    clockFace"}"
  -- Line 14 is `  s!"{two t.hour}:…"`: a name Lean doesn't know, after `s!"`.
  let e ← ed e ([AppEvent.key .home { ctrl := true }] ++ List.replicate 13 (key .down) ++
    List.replicate 5 (key .right) ++ [.text "NEW {oops} ", ctrl 'r'])
  IO.println s!"  `NEW \{oops}` on line 14, Ctrl+R: {e.note.quote}, {e.title}; marked: {marked e}"
  let e ← ed e (List.replicate 7 (key .backspace) ++ [ctrl 'r'])
  IO.println s!"  `\{oops} ` deleted, Ctrl+R: {e.note.quote}; marked: {marked e}"
  -- The desktop, with real runs: an editor from the menu, right of the
  -- clock, on Clock.lean.
  let feed := feed svc
  let settle := settle svc
  let item (x y : Float) (i : Nat) : Event := .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
  let ctrlE (ch : Char) : Event := .key (.char ch) { ctrl := true }
  let dkey (k : Key) : Event := .key k {}
  -- The REPL can't name the apps, but finds them in the menu's catalog.
  let launchLine := "do launch ((← world).catalog.lookup `LeanMachine.clock).get!"
  let (d, runs) ← feed start {} ([.press 120 200, .text launchLine, dkey .enter])
  let (d, _, seen) ← settle d runs
  IO.println s!"a REPL line, {launchLine}: {seen.map (·.showDone)}; windows {d.now.windows.map (·.title)}"
  let (d, runs) ← feed start {} [.tick ⟨10, 8, 30⟩, .menu 500 100, item 500 100 2]
  let (d, runs, _) ← settle d runs
  let (d, runs) ← feed d runs [.text "apps/cl", dkey .enter]
  let (d, runs, _) ← settle d runs
  let edWin := d.now.focus
  let win (d : Desktop) (id : Nat) : Option Win := d.now.windows.find? (·.id == id)
  let status (d : Desktop) (id : Nat) : String :=
    (((win d id).map (·.texts)).getD []).find? (·.startsWith "LeanMachine/") |>.getD "?"
  let clockSays (d : Desktop) : List String :=
    d.now.windows.filterMap fun w => if w.title == "Clock" then w.texts.getLast? else none
  let windows (d : Desktop) : List String := d.now.windows.map fun w =>
    s!"{w.id} {w.title}{match w.origin with | some n => s!" ({Editor.lastPart n})" | none => ""}"
  -- Ctrl+R, and the events that came back.
  let reloadOn (d : Desktop) (runs : Runs) : IO (Desktop × Runs) := do
    let t0 ← IO.monoNanosNow
    let (d, runs) ← feed d runs [ctrlE 'r']
    let (d, runs, seen) ← settle d runs
    IO.println s!"    {seen.map (·.showDone)} ({← ms t0} ms)"
    return (d, runs)
  IO.println s!"on the desktop: windows {windows d}; the clock says {clockSays d}"
  IO.println "  Ctrl+R on Clock.lean as it is:"
  let (d, runs) ← reloadOn d runs
  IO.println s!"    windows {windows d}; the clock says {clockSays d}; {d.past.length} earlier worlds"
  -- A press after `s!"` on line 14: the editor's body is at (503, 128).
  let (d, runs) ← feed d runs [.press (503 + Editor.textX + monoAdvance edFont * 5 + 1)
    (128 + Editor.rowY 13 + 9), .text "NEW "]
  IO.println "  `NEW ` typed in the clock's digits, Ctrl+R:"
  let (d, runs) ← reloadOn d runs
  IO.println s!"    the clock says {clockSays d}; the editor: {(status d edWin).quote}"
  render c d.view; shot c "reload-clock.png"
  let (d, runs) ← feed d runs [.key (.char 'z') ctrlShift]
  IO.println s!"  undo: the clock says {clockSays d}; the editor: {(status d edWin).quote}"
  let (d, runs) ← feed d runs [.text "{oops} "]
  IO.println "  `{oops} ` typed after it, Ctrl+R:"
  let (d, runs) ← reloadOn d runs
  IO.println s!"    the clock says {clockSays d}; the editor: {(status d edWin).quote}"
  render c d.view; shot c "reload-error.png"
  let (d, runs) ← feed d runs (List.replicate 7 (dkey .backspace))
  IO.println "  `{oops} ` deleted, Ctrl+R:"
  let (d, runs) ← reloadOn d runs
  IO.println s!"    the clock says {clockSays d}"
  -- Editor.lean, reloaded from the editor: a new editor opens beside it.
  let (d, runs) ← feed d runs [ctrlE 'o', ctrlE 'o', .text "apps/ed", dkey .enter]
  let (d, runs, _) ← settle d runs
  IO.println s!"  Editor.lean, Ctrl+R:"
  let (d, runs) ← reloadOn d runs
  IO.println s!"    windows {windows d}; focus {d.now.focus}"
  render c d.view; shot c "reload-editor.png"
  -- Again from the first editor, which still shows a strip at its left:
  -- the new one is replaced, in place.
  let (d, runs) ← feed d runs [.press 507 300]
  IO.println s!"  the first editor again ({(win d edWin).map (·.title)}), Ctrl+R:"
  let (d, runs) ← reloadOn d runs
  IO.println s!"    windows {windows d}"
  -- Ctrl+C 100 ms into a reload stops it.
  let (d, runs) ← feed d runs [ctrlE 'r']
  IO.sleep 100
  let t0 ← IO.monoNanosNow
  let (d, runs) ← feed d runs [ctrlE 'c']
  let (d, runs, seen) ← settle d runs
  IO.println s!"  Ctrl+R, then Ctrl+C 100 ms later: {seen.map (·.showDone)}, {← ms t0} ms after \
    Ctrl+C; the editor: {(status d edWin).quote}"
  -- A new app goes at the end of the menu, and opens beside the editor;
  -- the placeholders' file replaces Inspector and Notes in place.
  let (o, hello, _) ← reloadNow "Hello.lean" helloSrc
  let d := d.step (.reload edWin hello)
  IO.println s!"  Hello.lean ({o.show}): the menu {d.now.catalog.map (·.2.title)}; windows {windows d}"
  let placeholders := made.filter fun (n, _) => n == ``inspector || n == ``notes
  let d := d.step (.reload edWin placeholders)
  IO.println s!"  Placeholder.lean's apps: windows {windows d}, {d.past.length} earlier worlds"
  -- What reloaded code costs: it runs in Lean's interpreter, and starts
  -- every function at a safepoint, which nothing can stop on the loop's
  -- thread yet.
  IO.println "costs, compiled and reloaded:"
  let raw (file : String) : IO (App × Nat) := do
    let src ← IO.FS.readFile (projectRoot / s!"LeanMachine/Apps/{file}")
    let (_, apps, t) ← reloadNow file
      (src.replace "namespace LeanMachine" "set_option leanMachine.safepoints false\nnamespace LeanMachine")
    return ((apps.head?.map (·.2)).getD default, t)
  let (rawClock, rawClockMs) ← raw "Clock.lean"
  let (rawEditor, rawEditorMs) ← raw "Editor.lean"
  IO.println s!"  reloaded without safepoints: Clock.lean in {rawClockMs} ms, Editor.lean in {rawEditorMs} ms"
  let atTen := fun (a : App) => ((a.step (.tick ⟨10, 8, 30⟩)).map (·.1)).getD a
  for (name, a) in [("compiled", clock), ("reloaded", madeApp ``clock),
                    ("reloaded without safepoints", rawClock)] do
    let a := atTen a
    let us ← usPer 500 fun i => do
      if (a.view (230 + (i % 2).toFloat) 259).texts.isEmpty then IO.println "?"
    let drawUs ← usPer 200 fun i => do render c (a.view (230 + (i % 2).toFloat) 259)
    IO.println s!"  a {name} clock: the view in {us} µs, drawn in {drawUs} µs"
  for (name, a) in [("compiled", editor), ("reloaded", madeApp ``editor),
                    ("reloaded without safepoints", rawEditor)] do
    let a ← ([.tick ⟨10, 8, 30⟩, .text "apps/repl", key .enter] ++ List.replicate 120 (key .down)).foldlM
      (appNow svc) a
    let keyUs ← usPer 2000 fun i => do
      if let some (a', _) := a.step (.text (Char.ofNat (97 + i % 26)).toString) then
        if a'.title.isEmpty then IO.println "?"
    let downUs ← usPer 2000 fun i => do
      if let some (a', _) := a.step (key (if i == 100000 then .up else .down)) then
        if a'.title.isEmpty then IO.println "?"
    let viewUs ← usPer 200 fun i => do
      if (a.view (editorSize.1 + (i % 2).toFloat) editorSize.2).monos == 0 then IO.println "?"
    IO.println s!"  a {name} editor on {a.title}, line 121: a keystroke {keyUs} µs, Down {downUs} µs, \
      the view {viewUs} µs"
  -- Memory over many reloads: each one is a step undo can return to, and
  -- the apps in the worlds it keeps hold the Lean they came from.
  let (d, runs) ← feed d runs [.press 507 300, ctrlE 'o', .text "apps/cl", dkey .enter]
  let (d, runs, _) ← settle d runs
  let mut d := d
  let mut runs := runs
  for (file, n) in [("Clock.lean", 40), ("Editor.lean", 10)] do
    if file == "Editor.lean" then
      (d, runs) ← feed d runs [ctrlE 'o', .text "apps/ed", dkey .enter]
      let (d', runs', _) ← settle d runs
      d := d'; runs := runs'
    let rss0 ← rssMB
    let t0 ← IO.monoNanosNow
    for _ in [0:n] do
      (d, runs) ← feed d runs [ctrlE 'r']
      let (d', runs', _) ← settle d runs
      d := d'; runs := runs'
    let each := ((← IO.monoNanosNow) - t0) / 1000000 / n
    IO.println s!"{n} reloads of {file} from the editor, kept for undo: {each} ms each; RSS \
      {rss0} → {← rssMB} MB; windows {windows d}"

-- The edges named, as "left+bottom".
def LeanMachine.Edges.show (e : Edges) : String :=
  let names := [(e.left, "left"), (e.top, "top"), (e.right, "right"), (e.bottom, "bottom")]
  match names.filterMap fun (on, n) => if on then some n else none with
  | [] => "none"
  | ns => "+".intercalate ns

-- Resizing windows: by an edge, a corner and the grip, down to the
-- smallest size and up to the desktop's edges, with what the apps hear,
-- what's lit, and undo; an editor alone told sizes, its cursor kept in
-- view; an editor on the desktop made shorter, and undone; a reload that
-- keeps the size of the window it replaces the app in.
/-! ### Windows' places, for `testResize` and `testMaximize` -/

-- A whole number of pixels.
def showNum (f : Float) : String := if f < 0 then s!"-{(-f).toUInt32}" else toString f.toUInt32
def showRect (r : Rect) : String := s!"({showNum r.x}, {showNum r.y}) {showNum r.w} × {showNum r.h}"
def winTitled (d : Desktop) (title : String) : Option Win := d.now.windows.find? (·.title == title)
def rectOf (d : Desktop) (title : String) : String :=
  ((winTitled d title).map (showRect ·.rect)).getD "no such window"
-- What a window shows on a line that starts with `s`.
def says (d : Desktop) (title s : String) : String :=
  ((((winTitled d title).map (·.texts)).getD []).find? (·.startsWith s)).getD "?"
-- A press at (x, y), the pointer moved (dx, dy) in two motions, and a release.
def dragBy (x y dx dy : Float) : List Event :=
  [.press x y, .motion (x + dx / 2) (y + dy / 2), .motion (x + dx) (y + dy),
   .release (x + dx) (y + dy)]
def steps (d : Desktop) (es : List Event) : Desktop := es.foldl Desktop.step d
def undoKey : Event := .key (.char 'z') ctrlShift

def testResize (c : Canvas) (svc : Services) : IO Unit := do
  let n := showNum
  let drag := dragBy
  let win := winTitled
  let undo := undoKey
  let d := steps start [.tick ⟨10, 8, 30⟩]
  IO.println s!"resizing; the windows at the start: \
    {d.now.windows.map fun w => s!"{w.title} {showRect w.rect}"}"
  IO.println s!"  Notes as it opens: {(says d "Notes" "size:").quote}"
  let d := steps d (drag 915 595 180 100)
  IO.println s!"  Notes by its grip, (+180, +100): {rectOf d "Notes"}, \
    {(says d "Notes" "size:").quote}; {d.past.length} earlier worlds"
  let d := steps d (drag 600 350 (-50) (-20))
  IO.println s!"  Notes moved by its title, (-50, -20): {rectOf d "Notes"}, \
    {(says d "Notes" "size:").quote}"
  let d := steps d (drag 361 300 500 0)
  IO.println s!"  Inspector's left edge, +500: {rectOf d "Inspector"} (no narrower than \
    {n minW}), {(says d "Inspector" "size:").quote}"
  let d := steps d (drag 300 67 0 (-100))
  IO.println s!"  the REPL's top edge, grabbed 3 above it, -100: {rectOf d "REPL"} (stops at \
    the top)"
  let d := steps d (drag 222 448 (-100) 400)
  IO.println s!"  Clock's bottom left corner, (-100, +400): {rectOf d "Clock"} (stops at the bar); \
    {d.past.length} earlier worlds"
  let d := steps d [.motion 1051 500]
  IO.println s!"  the pointer 1 right of Notes: lit \
    {(d.now.lit.map fun (id, es) => s!"window {id}, {es.show}").getD "nothing"}"
  render c d.view; shot c "resize.png"
  let u := d.step undo
  IO.println s!"  undo: Clock {rectOf u "Clock"}; again: REPL {rectOf (u.step undo) "REPL"}"
  -- The editor alone, told its size.
  let key (k : Key) : AppEvent := .key k {}
  let ed (e : Editor) (evs : List AppEvent) : IO Editor := evs.foldlM (answerNow svc Editor.heard) e
  let e ← ed {} ([.tick ⟨10, 8, 30⟩, .resize 760 520, .text "apps/ed", key .enter] ++
    List.replicate 39 (key .down))
  IO.println s!"an editor alone on {e.title}, 760 × 520: {e.rows} rows, {e.cols} columns; \
    cursor on line {e.buffer.row + 1}, top line {e.top + 1}"
  let e ← ed e [.resize 760 200]
  IO.println s!"  told 760 × 200: {e.rows} rows; top line {e.top + 1}, so the cursor's is the last in view"
  let e ← ed e [.press (Editor.textX + 2) (edPad + edLineH * 2 + 5)]
  IO.println s!"  a press on the third row: cursor on line {e.buffer.row + 1}"
  let e ← ed e [.resize 300 520, key .«end»]
  IO.println s!"  told 300 × 520, End: {e.cols} columns; cursor at column {e.buffer.col + 1}, \
    first column in view {e.left + 1}"
  let e ← ed e [.resize (minW - 2 * frame) (minH - titleH - frame)]
  IO.println s!"  told the smallest size, {n (minW - 2 * frame)} × {n (minH - titleH - frame)}: \
    {e.rows} rows, {e.cols} columns; top line {e.top + 1}, first column {e.left + 1}"
  -- The editor on the desktop, on Clock.lean, its cursor on line 31, made
  -- 300 shorter by its bottom edge.
  let item (x y : Float) (i : Nat) : Event := .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
  let dkey (k : Key) : Event := .key k {}
  let d ← ([Event.menu 300 100, item 300 100 2, .text "apps/cl", dkey .enter] ++
    List.replicate 30 (dkey .down)).foldlM (stepNow svc) start
  -- The line numbers in view, first and last.
  let numbers (d : Desktop) : String :=
    let ns := (((win d "Clock.lean").map (·.texts)).getD []).filter fun s =>
      s.length == gutterCols - 1 && !s.trimAscii.isEmpty && s.trimAscii.toString.all Char.isDigit
    s!"lines {(ns.head?.map (·.trimAscii.toString)).getD "?"} to \
      {(ns.getLast?.map (·.trimAscii.toString)).getD "?"} in view"
  IO.println s!"an editor on the desktop, on Clock.lean: {rectOf d "Clock.lean"}, {numbers d}"
  let d ← (drag 600 649 0 (-300)).foldlM (stepNow svc) d
  IO.println s!"  its bottom edge 300 up: {rectOf d "Clock.lean"}, {numbers d}; \
    {(says d "Clock.lean" "LeanMachine/").quote}"
  render c d.view; shot c "resize-editor.png"
  let d := d.step undo
  IO.println s!"  undo: {rectOf d "Clock.lean"}, {numbers d}"
  -- A reload keeps the size of the window it puts the new app in.
  let d ← (drag 221 300 (-120) 0 ++ [Event.press 700 110, .release 700 110,
    .key (.char 'r') { ctrl := true }]).foldlM (stepNow svc) d
  IO.println s!"  Clock's left edge -120, then Ctrl+R in the editor: Clock {rectOf d "Clock"}; \
    {(says d "Clock.lean" "LeanMachine/").quote}"

-- Maximizing and restoring: by the box on a title, a double click on
-- it and Ctrl+Shift+M, each undone; a maximized window dragged by its
-- title (restored under the pointer, past a nudge) and by an edge; a
-- reload that keeps a window maximized; an editor maximized.
def testMaximize (c : Canvas) (svc : Services) : IO Unit := do
  let start := steps start [.tick ⟨10, 8, 30⟩]
  let state (d : Desktop) (title : String) : String :=
    match winTitled d title with
    | some w => s!"{showRect w.rect}{if w.maximized then ", maximized" else ""}"
    | none => "no such window"
  let mkey : Event := .key (.char 'm') ctrlShift
  let click (x y : Float) : List Event := [.press x y, .release x y]
  -- Notes (500, 340) 420 × 260: its maximize box is at (885, 354).
  let d := steps start (click 885 354)
  IO.println s!"maximizing; Notes' box: {state d "Notes"}, \
    {(says d "Notes" "size:").quote}; {d.past.length} earlier worlds"
  let d := steps d (click (screenW - 35) 14)
  IO.println s!"  its box again: {state d "Notes"}, {(says d "Notes" "size:").quote}"
  -- Clock (220, 160) 236 × 290; its title is in front at (300, 170).
  let d := steps start (click 300 170 ++ [.press 300 170 2, .release 300 170])
  IO.println s!"  a double click on Clock's title: {state d "Clock"}; \
    {d.past.length} earlier worlds"
  IO.println s!"  undo: {state (d.step undoKey) "Clock"}"
  let d := steps d (click 300 10 ++ [.press 300 10 2, .release 300 10])
  IO.println s!"  a double click on it again: {state d "Clock"}"
  -- The REPL's title at (150, 80), then Ctrl+Shift+M.
  let d := steps start (click 150 80 ++ [mkey])
  IO.println s!"  Ctrl+Shift+M on the REPL: {state d "REPL"}; {d.past.length} earlier worlds"
  IO.println s!"  undo: {state (d.step undoKey) "REPL"}"
  -- Inspector (360, 250) 420 × 260, maximized, then dragged by its title
  -- from the middle of the screen.
  let d := steps start (click 500 260 ++ [mkey, .press 640 14, .motion 642 15])
  IO.println s!"  Inspector maximized, its title pressed in the middle and nudged 2: \
    {state d "Inspector"}"
  let d := steps d [.motion 640 114, .release 640 114]
  IO.println s!"  then 100 down: {state d "Inspector"}, {(says d "Inspector" "size:").quote} \
    (the pointer as far along its title as before)"
  let d := steps d ([mkey] ++ dragBy (screenW - 2) 400 (-300) 0)
  IO.println s!"  maximized again, its right edge -300: {state d "Inspector"}"
  -- A reload keeps a window maximized, and its place to go back to.
  let d := steps start (click 300 170 ++ [mkey])
  let d := d.step (.reload 0 [(``clock, clock)])
  IO.println s!"  Clock maximized, then reloaded: {state d "Clock"}"
  let d := steps d (click (screenW - 35) 14)
  IO.println s!"  its box: {state d "Clock"}"
  -- An editor on Clock.lean, maximized.
  let item (x y : Float) (i : Nat) : Event := .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
  let d ← [Event.menu 300 100, item 300 100 2, .text "apps/cl", .key .enter {}, mkey].foldlM
    (stepNow svc) start
  let rows := (((winTitled d "Clock.lean").map (·.texts)).getD []).filter fun s =>
    s.length == gutterCols - 1 && !s.trimAscii.isEmpty && s.trimAscii.toString.all Char.isDigit
  IO.println s!"  an editor on Clock.lean, Ctrl+Shift+M: {state d "Clock.lean"}, \
    {rows.length} lines in view"
  render c d.view; shot c "maximize.png"

-- Minimizing and the taskbar: the bar at the start; Notes minimized by
-- its box and brought back by its button, minimized by its button, and
-- undone; Ctrl+Shift+H until nothing is focused, then once more; a
-- maximized clock minimized, ticked, reloaded and brought back
-- maximized; a click on a button below a maximized window's edge, and on
-- the bar over a window under it; the hint giving way to more windows;
-- the boxes on a title showing what they do, with the pointer on them.
def testMinimize (c : Canvas) : IO Unit := do
  let start := steps start [.tick ⟨10, 8, 30⟩]
  let click (x y : Float) : List Event := [.press x y, .release x y]
  -- The middle of the button of the window titled `title`.
  let buttonX (d : Desktop) (title : String) : Float :=
    let bar := d.now.taskbar
    ((bar.buttons.find? (·.1.title == title)).map fun (_, x) => x + bar.w / 2).getD 0
  let button (d : Desktop) (title : String) : List Event :=
    click (buttonX d title) (barY + barH / 2)
  let focused (d : Desktop) : String :=
    ((d.now.windows.find? (·.id == d.now.focus)).map (·.title)).getD "nothing"
  let front (d : Desktop) : String := ((d.now.visible.getLast?.map (·.title))).getD "nothing"
  let state (d : Desktop) (title : String) : String :=
    match winTitled d title with
    | some w => s!"{showRect w.rect}{if w.maximized then ", maximized" else ""}\
        {if w.minimized then ", minimized" else ""}"
    | none => "no such window"
  let bar (d : Desktop) : String :=
    let b := d.now.taskbar
    s!"{d.now.windows.length} windows, buttons {showNum b.w} wide, the hint \
      {if b.hint then "shown" else "gone"}"
  let hkey : Event := .key (.char 'h') ctrlShift
  let mkey : Event := .key (.char 'm') ctrlShift
  IO.println s!"the taskbar: {bar start}, at \
    {start.now.taskbar.buttons.map fun (w, x) => s!"{w.title} {showNum x}"}; focus on {focused start}"
  -- Notes (500, 340) 420 × 260: its minimize box is at (862, 354).
  let d := steps start (click 862 354)
  IO.println s!"minimizing; Notes' box: {state d "Notes"}; focus on {focused d}; \
    {d.past.length} earlier worlds; a press where it was finds \
    {((d.now.grabAt 880 580).map (·.1.title)).getD "nothing"}"
  render c (d.step (.motion (buttonX d "Clock") (barY + 10))).view; shot c "taskbar.png"
  let d := steps d (button d "Notes")
  IO.println s!"  its button: {state d "Notes"}; in front {front d}; focus on {focused d}; \
    {d.past.length} earlier worlds"
  let d := steps d (button d "Notes")
  IO.println s!"  its button again: {state d "Notes"}; focus on {focused d}"
  let u := d.step undoKey
  IO.println s!"  undo: {state u "Notes"}; focus on {focused u}"
  let d := steps d [hkey]
  IO.println s!"  Ctrl+Shift+H: Inspector {state d "Inspector"}; focus on {focused d}"
  let d := steps d [hkey, hkey]
  IO.println s!"  twice more: focus on {focused d}; {d.now.visible.length} windows showing; \
    {d.past.length} earlier worlds"
  let d := steps d [hkey]
  IO.println s!"  once more, nothing focused: {d.past.length} earlier worlds"
  let d := steps d (button d "Inspector")
  IO.println s!"  Inspector's button: {state d "Inspector"}; focus on {focused d}"
  -- Clock (220, 160): maximized, minimized and ticked while minimized.
  let d := steps start (click 300 170 ++ [mkey, hkey, .tick ⟨10, 9, 0⟩])
  IO.println s!"Clock maximized, Ctrl+Shift+H, a tick at 10:09:00: {state d "Clock"}; \
    focus on {focused d}"
  let d := steps d (button d "Clock")
  IO.println s!"  its button: {state d "Clock"}; it says {(says d "Clock" "10:").quote}"
  let d := (steps d (button d "Clock")).step (.reload 0 [(``clock, clock)])
  IO.println s!"  its button again, then reloaded: {state d "Clock"}"
  let d := steps d (button d "Clock")
  IO.println s!"  its button: {state d "Clock"}"
  let d := steps d (click (screenW - 35) 14)
  IO.println s!"  its green box: {state d "Clock"}"
  -- Inspector maximized: its bottom edge, which can be grabbed from 4
  -- below it, is at the top of the bar. The pointer 2 below it, on
  -- Clock's button.
  let d := steps start (click 500 260 ++ [mkey])
  let d := steps d [.motion (buttonX d "Clock") (barY + 2)]
  IO.println s!"Inspector maximized, the pointer 2 into the bar on Clock's button: lit \
    {(d.now.lit.map fun (id, es) => s!"window {id}, {es.show}").getD "nothing"}"
  let d := steps d (click (buttonX d "Clock") (barY + 2))
  IO.println s!"  a click there: focus on {focused d}, in front {front d}; Inspector {state d "Inspector"}"
  -- Notes dragged 300 down, under the bar, then Clock's title clicked.
  let d := steps start (dragBy 600 350 0 300 ++ click 300 170)
  let before := d.past.length
  let d := steps d (click 900 790)
  IO.println s!"Notes under the bar, {state d "Notes"}; a click on the bar over it, off the \
    buttons: focus on {focused d}, in front {front d}, {d.past.length - before} more earlier worlds"
  let d := steps d (dragBy 600 650 0 300)
  IO.println s!"  Notes dragged 300 further down: {state d "Notes"}, its title's top \
    {showNum titleKept} above the bar"
  -- More windows, from the menu: Clock, Inspector, Notes, Clock.
  let item (x y : Float) (i : Nat) : Event := .press (x + 20) (Menu.itemY ⟨x, y⟩ i + itemH / 2)
  let mut more := start
  for (i, k) in [(0 : Nat), 3, 4, 0].zipIdx do
    let x := 640 + 30 * k.toFloat
    let y := 60 + 30 * k.toFloat
    more := steps more [.menu x y, item x y i]
    IO.println s!"  {bar more}"
  let d := more
  let d := steps d (button d "REPL" ++ button d "REPL" ++ button d "Inspector" ++ button d "Inspector")
  let d := d.step (.motion (buttonX d "Notes") (barY + 10))
  IO.println s!"  REPL and the first Inspector minimized: focus on {focused d}"
  render c d.view; shot c "taskbar-many.png"
  -- The pointer on the boxes of a title, which show what they do. The
  -- REPL (80, 70) 566 × 331, behind: its boxes from x = 580 to its right
  -- edge at 646, its title from y = 70 to 98.
  let boxesAt (d : Desktop) (x y : Float) : String :=
    let d := d.step (.motion x y)
    ((d.now.boxesLit.bind fun id => d.now.windows.find? (·.id == id)).map (·.title)).getD "none"
  IO.println s!"the boxes lit with the pointer on the REPL's minimize box: \
    {boxesAt start 590 84}; on its title left of them: {boxesAt start 570 84}; on its top \
    edge above them: {boxesAt start 630 71}; on its right edge: {boxesAt start 644 84}"
  render c (start.step (.motion 610 84)).view; shot c "boxes.png"
  let d := steps start (click 885 354)
  IO.println s!"  Notes maximized, the pointer on its green box: {boxesAt d (screenW - 36) 14}"
  render c (d.step (.motion (screenW - 36) 14)).view; shot c "boxes-max.png"

/-! ### Frames, for `testFrames` -/

-- A hand that the frames it hears turn, once every π seconds, with the
-- last frame's time in its title.
def spinner : App :=
  App.asking "Spin" (0 : Nat) (fun _ e => match e with | .frame ms => some (ms, []) | _ => none)
    (fun ms w h =>
      let a := ms.toFloat / 500
      .line (w / 2) (h / 2) (w / 2 + 80 * a.cos) (h / 2 + 80 * a.sin) 4 0xf7768e)
    (titleOf := fun ms => s!"Spin {ms}") (animating := fun _ => true)

-- A spinner made in the REPL, as docs/explore/spinner.md types it.
def spinnerLines : List String :=
  ["def hand (ms : Nat) (w h : Float) : Picture := let a := ms.toFloat / 500; \
      .line (w / 2) (h / 2) (w / 2 + 80 * a.cos) (h / 2 + 80 * a.sin) 4 0xf7768e",
   "def hear : Nat → AppEvent → Option Nat | _, .frame ms => some ms | _, _ => none",
   "launch (App.of \"Spin\" 0 hear hand (animating := fun _ => true))"]

def testFrames (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "frames:"
  let start := steps start [.tick ⟨10, 8, 30⟩]
  let spin (d : Desktop) : String :=
    ((d.now.windows.find? (·.title.startsWith "Spin")).map (·.title)).getD "none"
  let focused (d : Desktop) : String :=
    ((d.now.windows.find? (·.id == d.now.focus)).map (·.title)).getD "none"
  IO.println s!"  the start desktop animates: {start.now.animating}"
  -- A spinner, as a run in the REPL (window 1) would open it.
  let d := steps start [.launch 1 spinner, .frame 1000, .frame 1017]
  IO.println s!"  a spinner opened, focus on {focused d}: animates {d.now.animating}; \
    after frames at 1000 and 1017 ms: {spin d}; earlier worlds {d.past.length}, as before \
    {start.past.length}"
  render c d.view; shot c "frames.png"
  -- Minimized, it hears no frames, and the desktop doesn't animate.
  let dm := steps d [.key (.char 'h') ctrlShift, .frame 2000]
  IO.println s!"  minimized: animates {dm.now.animating}; after a frame at 2000 ms: {spin dm}"
  let db := steps dm [undoKey, .frame 3000]
  IO.println s!"  undone: animates {db.now.animating}; after a frame at 3000 ms: {spin db}"
  -- Made in the REPL: compiled there, and turned by the same frames.
  let mut d := start
  let mut seen := []
  for line in spinnerLines do
    let (d', runs) ← feed svc d {} [.press 120 200, .text line, .key .enter {}]
    let (d', _, ended) ← settle svc d' runs
    d := d'; seen := seen ++ ended
  IO.println s!"  a spinner made in the REPL: {seen.map (·.showDone)}; windows \
    {d.now.windows.map (·.title)}; animates {d.now.animating}"
  render c (steps d [.frame 700]).view; shot c "frames-repl.png"

/-! ## `--bench`: Boids' step -/

section Bench
open LeanMachine.Boids

-- `n` boids placed and set going by whole-number arithmetic, so that
-- any language can make the same flock: Schevana's Boids in Chez steps
-- this one too, and prints the same sums if it steps it the same way.
def benchFlock (n : Nat) : Flock :=
  (Array.range n).map fun i =>
    ⟨⟨((i * 7919) % 1200).toFloat + 0.5, ((i * 6007) % 700).toFloat + 0.5⟩,
     ⟨((i * 31) % 41).toFloat / 10 - 2, ((i * 17) % 37).toFloat / 9 - 2⟩⟩

-- The rules that make a step do the most: every rule on, as strong and
-- as far-seeing as the ranges go. Schevana's benchmarks call them the
-- heaviest.
def heaviest : Rules :=
  { cohesion := 0.2, cohesionRadius := 200, alignment := 1, alignmentRadius := 200,
    separation := 1, separationRadius := 50, viewAngle := 360,
    clearView := 1, backOff := 1, blockerRadius := 100, blockerCone := 180 }

-- The milliseconds a frame's step takes (`Flock.stepOn`, on a field of
-- 1200 × 700): 10 steps, then the mean of 30 more. After them, the bits
-- of the sum of every boid's position, to compare across languages.
def benchBoids : IO Unit := do
  IO.println "Boids: ms a step of Flock.stepOn on 1200 × 700, the mean of 30 after 10"
  let sum (flock : Flock) := flock.foldl (fun s b => s + b.position.x + b.position.y) 0
  for n in [150, 300, 500, 1000] do
    for (name, rules) in [("default", ({} : Rules)), ("heaviest", heaviest)] do
      let steps (flock : Flock) (k : Nat) := k.repeat (·.stepOn rules 1200 700) flock
      let warm := steps (benchFlock n) 10
      let t0 ← IO.monoNanosNow
      let flock := steps warm 30
      let ms := ((← IO.monoNanosNow) - t0).toFloat / 30 / 1e6
      let bits := String.ofList ((Nat.toDigits 16 (sum flock).toBits.toNat).map Char.toUpper)
      IO.println s!"{n} {name}: {ms} ms a step, after 40: {bits}"

end Bench

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
    test c svc; testResize c svc; testMaximize c svc; testMinimize c; testFrames c svc; testLean c svc; testEditor c svc; testReload c svc; testRuns c svc; testMasking
  | ["--bench"] =>
    let _ ← IO.wait base
    benchBoids
  | ["--frames", n] =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c svc start {} n.toNat?
  | _ =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c svc start {} none
