import LeanMachine.Host
import LeanMachine.Runs
import LeanMachine.View

-- A desktop as a value. `World.step` and `Desktop.view` are pure (in
-- LeanMachine/); the loop here does the I/O, with `Runs`
-- (LeanMachine/Runs.lean) doing what apps ask, and `render`
-- (LeanMachine/Host.lean) is the only code that draws.

open LeanMachine

/-! ## The loop: the I/O -/

-- Steps the desktop through `es`, and does what its apps ask as they ask
-- it. A request answered at once (a stop with no run to stop) is stepped
-- through after the rest. `wake` is what a run calls when it ends.
partial def feed (wake : IO Unit) (d : Desktop) (runs : Runs) :
    List Event → IO (Desktop × Runs)
  | [] => return (d, runs)
  | e :: rest => do
    let (d, asked) := (d.step e).takeAsked
    let mut runs := runs
    let mut answers := []
    for a in asked do
      let (rs, more) ← runs.handle wake a
      runs := rs
      answers := answers ++ more
    feed wake d runs (rest ++ answers)

-- Applies every waiting event, the outcomes of runs that ended, and a
-- tick with the time, then draws once. `frames` stops it early (for
-- tests); the window's close button or Esc stops it any time.
partial def run (c : Canvas) (d : Desktop) (runs : Runs) (frames : Option Nat) :
    IO Unit := do
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
      else (d, runs) ← feed Host.wake d runs [.key .escape m]
    | some e => (d, runs) ← feed Host.wake d runs [e]
    | none => pure ()
    raw ← Host.event 0
  if quit then runs.stopAll; return
  -- Runs that ended tell their windows how. Runs whose window is gone
  -- are stopped.
  let (rs, ended) ← runs.collect
  (d, runs) ← feed Host.wake d rs ended
  runs ← runs.keepFor (d.now.windows.map (·.id))
  let (t, _) ← localTime
  (d, runs) ← feed Host.wake d runs [.tick t]
  render c d.view
  Host.present c
  run c d runs (frames.map (· - 1))

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

-- The REPL after `e`, with any run it asks for done at once, here: the
-- work is a pure function, so a test needs no thread.
def hearNow (r : Repl) (e : AppEvent) : Repl :=
  match r.step e with
  | none => r
  | some (r, asks) => asks.foldl (init := r) fun r a =>
    let answer : AppEvent := match a with
      | .run tag work => .done tag (.value (work ())) 0
      | .stop tag => .done tag .stopped 0
    ((r.step answer).map (·.1)).getD r

-- The desktop after `e`, with every run its apps ask for done at once,
-- here, the same way.
partial def stepNow (d : Desktop) (e : Event) : Desktop :=
  let (d, asked) := (d.step e).takeAsked
  asked.foldl (init := d) fun d a => stepNow d <| match a.request with
    | .run tag work => .done a.win tag (.value (work ())) 0
    | .stop tag => .done a.win tag .stopped 0

-- The pure world, driven by a script of events instead of a person.
def test (c : Canvas) : IO Unit := do
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
  -- The REPL, typed into and edited: first as a pure `Repl`, then on the
  -- desktop after a press in its body (left of Clock) focuses it.
  let key (k : Key) : AppEvent := .key k {}
  let line (s : String) : List AppEvent := [.text s, key .enter]
  let typing : List AppEvent :=
    line "1 + 1" ++
    [.text "helo", key .left, .text "l",                   -- hello
     key .home, .text "say ", key .«end», .text "!", key .enter,
     .text "xabc", key .home, key .delete, key .enter,     -- abc
     key .backspace, key .enter] ++                        -- empty: no echo
    (List.range 10).flatMap (fun i => line s!"line {i + 1}") ++
    line (String.join (List.replicate 14 "0123456789")) ++ -- wraps
    [.text "draft", key .up, key .up, key .down, key .down, -- the draft again
     key .left, key .left]
  let r := typing.foldl hearNow ({} : Repl)
  let entry : Entry → String
    | .note s => s!"note {s.quote}"
    | .input s => s!"> {s}"
    | .output s => s
  IO.println s!"REPL line {(String.ofList (r.line.before.reverse ++ '|' :: r.line.after)).quote}, \
    {r.history.length} lines of history, \
    transcript starts {(r.transcript.reverse.take 7).map entry}"
  let r := [key .up, key .up, key .up].foldl hearNow r
  IO.println s!"three Ups: {r.line.text.quote}"
  let toEvent : AppEvent → Option Event
    | .text s => some (.text s)
    | .key k m => some (.key k m)
    | _ => none
  let d := (Event.press 120 200 :: typing.filterMap toEvent).foldl stepNow start
  IO.println s!"focused: {(d.now.windows.find? (·.id == d.now.focus)).map (·.title)}"
  render c d.view; c.savePng "repl.png"

def LeanMachine.Request.show : Request → String
  | .run tag _ => s!"run {tag}"
  | .stop tag => s!"stop {tag}"

def LeanMachine.Event.showDone : Event → String
  | .done win tag o ms =>
    let how := match o with
      | .value s => s!"value {s}"
      | .stopped => "stopped"
      | .failed why => s!"failed: {why}"
    s!"window {win} run {tag}: {how}, {ms} ms"
  | _ => "another event"

def rssMB : IO Nat := do
  let s ← IO.FS.readFile "/proc/self/status"
  let line := ((s.splitOn "\n").find? (·.startsWith "VmRSS:")).getD ""
  let kb := ((line.drop 6).trimAscii.toString.takeWhile Char.isDigit).toNat!
  return kb / 1024

-- Waits for every run to end, up to `ms`, and tells the desktop how each
-- did; also returns the outcomes, oldest first.
partial def settle (d : Desktop) (runs : Runs) (ms : Nat := 20000)
    (seen : List Event := []) : IO (Desktop × Runs × List Event) := do
  let (runs, ended) ← runs.collect
  let (d, runs) ← feed (pure ()) d runs ended
  let seen := seen ++ ended
  if runs.live.isEmpty || ms == 0 then return (d, runs, seen)
  IO.sleep 1
  settle d runs (ms - 1) seen

-- Runs on real threads, driven by a script: the desktop's REPL asks for
-- busy work, Ctrl+C stops it, and the outcomes come back to it.
def testRuns (c : Canvas) : IO Unit := do
  let feed := feed (pure ())
  let ctrlC := Event.key (.char 'c') { ctrl := true }
  let enter (s : String) : List Event := [.text s, .key .enter {}]
  let ms (t0 : Nat) : IO Nat := return ((← IO.monoNanosNow) - t0) / 1000000
  let rss0 ← rssMB
  -- A press in the REPL's body focuses it.
  let (d, runs) ← feed start {} [.press 120 200]
  -- What the REPL asks for, as the world hands it to the loop.
  let (_, asked) := ((enter "alloc 5").foldl Desktop.step d).takeAsked
  IO.println s!"Enter asks for: {asked.map fun a => s!"{a.request.show} from window {a.win}"}"
  -- An empty line asks for nothing. A run that does nothing: from asking
  -- to its end, a thread started and gone.
  let (d, runs) ← feed d runs (enter "")
  let t0 ← IO.monoNanosNow
  let (d, runs) ← feed d runs (enter "ok")
  for l in runs.live do let _ ← IO.wait l.task
  IO.println s!"a run that does nothing, there and back: {((← IO.monoNanosNow) - t0) / 1000} µs"
  let (d, runs, _) ← settle d runs
  -- Each kind of busy work, stopped by Ctrl+C after 300 ms.
  let mut d := d
  let mut runs := runs
  for line in ["alloc 2000", "poll 50000", "spin 400"] do
    (d, runs) ← feed d runs (enter line)
    IO.sleep 300
    if line == "alloc 2000" then
      render c d.view; c.savePng "repl-running.png"
    let t0 ← IO.monoNanosNow
    (d, runs) ← feed d runs [ctrlC]
    let (d', runs', seen) ← settle d runs
    d := d'; runs := runs'
    IO.println s!"{line}, Ctrl+C at 300 ms: {seen.map (·.showDone)}, \
      {← ms t0} ms after Ctrl+C"
  -- Work that ends by itself, then Ctrl+C with nothing running: it
  -- clears the line.
  (d, runs) ← feed d runs (enter "alloc 20")
  let (d', runs', seen) ← settle d runs
  d := d'; runs := runs'
  IO.println s!"alloc 20: {seen.map (·.showDone)}"
  (d, runs) ← feed d runs ([.text "never entered"] ++ [ctrlC])
  render c d.view; c.savePng "repl-runs.png"
  -- Undo brings back a REPL waiting for a run whose outcome came to a
  -- world that's gone. Ctrl+C is answered at once.
  (d, runs) ← feed d runs (enter "alloc 1")
  (d, runs) ← feed d runs [.press 120 200]   -- a press: undo returns here
  let (d', runs', _) ← settle d runs
  (d, runs) ← feed d' runs' [.key (.char 'z') ctrlShift]
  let (d', asked) := (d.step ctrlC).takeAsked
  let mut answers := []
  for a in asked do
    let (rs, more) ← runs.handle (pure ()) a
    runs := rs; answers := answers ++ more
  IO.println s!"after undo, Ctrl+C asks {asked.map (·.request.show)} with \
    {runs.live.length} runs going; answered at once: {answers.map (·.showDone)}"
  (d, runs) ← feed d' runs answers
  render c d.view; c.savePng "repl-undo.png"
  -- A frame, drawn while a run allocates as fast as it can, and without.
  let frameUs (d : Desktop) : IO Nat := do
    let t0 ← IO.monoNanosNow
    for _ in [0:20] do render c d.view
    return ((← IO.monoNanosNow) - t0) / 20000
  let quiet ← frameUs d
  (d, runs) ← feed d runs (enter "alloc 5000")
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
      | .ok (some s, _) => s!"finished with {s}"
      | .error e => toString e
    IO.println s!"closing the REPL: its run {how} {← ms t0} ms later, \
      {runs.live.length} runs going"
  -- What stops leak: 50 runs stopped as they allocate.
  let rss1 ← rssMB
  (d, runs) ← feed start runs [.press 120 200]
  for _ in [0:50] do
    (d, runs) ← feed d runs (enter "alloc 1000")
    IO.sleep 20
    (d, runs) ← feed d runs [ctrlC]
    let (d', runs', _) ← settle d runs
    d := d'; runs := runs'
  IO.println s!"RSS: {rss0} MB at the start, {rss1} MB after the runs above, \
    {← rssMB} MB after 50 more stopped"

def main (args : List String) : IO Unit := do
  let c ← Canvas.new screenW.toUInt32 screenH.toUInt32
  match args with
  | ["--test"] => test c; testRuns c
  | ["--frames", n] =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c start {} n.toNat?
  | _ =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c start {} none
