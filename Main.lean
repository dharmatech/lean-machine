import LeanMachine.Host
import LeanMachine.Runs
import LeanMachine.Eval
import LeanMachine.View

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

-- Applies every waiting event, the outcomes of runs that ended, and a
-- tick with the time, then draws once. `frames` stops it early (for
-- tests); the window's close button or Esc stops it any time.
partial def run (c : Canvas) (svc : Services) (d : Desktop) (runs : Runs)
    (frames : Option Nat) : IO Unit := do
  if frames == some 0 then runs.stopAll; return
  let mut d := d
  let mut runs := runs
  let mut quit := false
  -- Waits for an event, but not past 100 ms or the start of the next
  -- second, so a clock turns over on time. A run that ends wakes it.
  let (_, msLeft) ← localTime
  let mut raw ← Host.event (min 100 (msLeft + 1)).toUInt32
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
  render c d.view
  Host.present c
  run c svc d runs (frames.map (· - 1))

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

-- The REPL after `e`, with what it asks for worked out at once, on this
-- thread, outside any run.
def hearNow (svc : Services) (r : Repl) (e : AppEvent) : IO Repl := do
  match r.step e with
  | none => return r
  | some (r, asks) => asks.foldlM (init := r) fun r a => do
    let answer : AppEvent ← match a with
      | .run tag work => pure (.done tag (.value (work ())) 0)
      | .eval tag src env => do
        pure (.done tag (← svc.eval src env (← IO.CancelToken.new)) 0)
      | .stop tag => pure (.done tag (.stopped [] false) 0)
    return ((r.step answer).map (·.1)).getD r

-- The desktop after `e`, with the runs its apps ask for ended.
def stepNow (svc : Services) (d : Desktop) (e : Event) : IO Desktop := do
  let (d, runs) ← feed svc d {} [e]
  let (d, _, _) ← settle svc d runs
  return d

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
                 item 100 400 3,                    -- Notes
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
  render c d.view; c.savePng "after-script.png"
  -- The menu open, the pointer on its second item.
  let open_ := (d.step (.menu 700 250)).step
    (.motion 720 (Menu.itemY ⟨700, 250⟩ 1 + 5))
  render c open_.view; c.savePng "menu.png"
  let off := open_.step (.press 20 20)
  IO.println s!"a press off the menu: menu open {off.now.menu.isSome}, \
    {off.now.windows.length} windows, {off.past.length} earlier worlds"
  let undo := Event.key (.char 'z') ctrlShift
  let d := (d.step undo).step undo
  IO.println s!"after two undos: {d.now.windows.map (·.title)}"
  render c d.view; c.savePng "after-undo.png"
  render c sampler; c.savePng "sampler.png"
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
  render c d.view; c.savePng "repl.png"

def LeanMachine.Request.show : Request → String
  | .run tag _ => s!"run {tag}"
  | .eval tag src _ => s!"eval {tag} {src.quote}"
  | .stop tag => s!"stop {tag}"

def LeanMachine.Said.show : Said → String
  | .info s => s
  | .warning s => s!"warning: {s}"
  | .error s => s!"error: {s}"

def LeanMachine.Event.showDone : Event → String
  | .done win tag o ms =>
    let how := match o with
      | .value s => s!"value {s}"
      | .evaluated said _ => s!"said {said.map Said.show}"
      | .stopped said cleanly =>
        s!"stopped{if cleanly then " cleanly" else ""}\
          {if said.isEmpty then "" else s!", said {said.map Said.show}"}"
      | .failed why => s!"failed: {why}"
    s!"window {win} run {tag}: {how}, {ms} ms"
  | .launch win app => s!"window {win} opened {app.title}"
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
     "(·.windows.map (·.title)) <$> world", "IO.println \"printed\"",
     "#eval [1, 2, 3].map sq"]
  -- Enters a line, presses Ctrl+C 300 ms later, and says how the run
  -- ended and how long after Ctrl+C.
  let stopAt (d : Desktop) (runs : Runs) (line : String) (png : Option String := none) :
      IO (Desktop × Runs) := do
    let (d, runs) ← feed d runs (enter line)
    IO.sleep 300
    if let some file := png then render c d.view; c.savePng file
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
  render c d.view; c.savePng "repl-runs.png"
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
  render c d.view; c.savePng "repl-interrupt.png"
  -- An app made here opens in a window by the REPL, and runs there: a
  -- press drops a dot.
  (d, runs) ← lines d runs
    ["launch (App.of \"Dots\" ([] : List (Float × Float)) \
       (fun s e => match e with | .press x y => some ((x, y) :: s) | _ => none) \
       fun s _ _ => .group (s.map fun (x, y) => .circle x y 6 0xe0af68))"]
  (d, runs) ← feed d runs [.press (123 + 60) (138 + 50), .press (123 + 120) (138 + 90)]
  IO.println s!"windows: {d.now.windows.map (·.title)}, focus on \
    {(d.now.windows.find? (·.id == d.now.focus)).map (·.title)}"
  render c d.view; c.savePng "repl-launch.png"
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
  render c d.view; c.savePng "repl-undo.png"
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
  render c d.view; c.savePng "repl-highlight.png"
  let d ← [.key (.char 'c') { ctrl := true }, .text "Picture.", key .tab].foldlM (stepNow svc) d
  render c d.view; c.savePng "repl-complete.png"
  let d ← [.key (.char 'c') { ctrl := true }, .text "List.ma", key .tab].foldlM (stepNow svc) d
  render c d.view; c.savePng "repl-complete-many.png"
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

def main (args : List String) : IO Unit := do
  let c ← Canvas.new screenW.toUInt32 screenH.toUInt32
  -- The REPLs' Lean is imported in the background; the first line waits
  -- for it.
  let t0 ← IO.monoNanosNow
  let base ← startBase
  let svc : Services := { wake := Host.wake, eval := LeanMachine.eval base }
  match args with
  | ["--test"] =>
    let _ ← IO.wait base
    IO.println s!"the REPLs' Lean imported in {((← IO.monoNanosNow) - t0) / 1000000} ms, \
      RSS {← rssMB} MB"
    test c svc; testLean c svc; testRuns c svc; testMasking
  | ["--frames", n] =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c svc start {} n.toNat?
  | _ =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c svc start {} none
