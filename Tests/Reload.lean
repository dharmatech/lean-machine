import Tests.Kit

/-! # `--test`: reloading apps

Each app's file reloaded in the desktop's Lean, files that can't be,
an editor alone, then the desktop with real runs: Clock, Editor and
Boids reloaded from an editor, an error, a stop, a new app (`helloSrc`),
and what reloaded code costs (docs/design/reloading/README.md). -/

namespace LeanMachine.Tests

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
-- app; Boids.lean edited and reloaded into an open flock, over the
-- compiled simulation, whose files can't be reloaded; then what reloaded
-- code costs to run, and memory over many reloads.
def testReload (c : Canvas) (svc : Services) : IO Unit := do
  let ms (t0 : Nat) : IO Nat := return ((← IO.monoNanosNow) - t0) / 1000000
  let reloadNow (path src : String) : IO (Outcome × List (Lean.Name × App) × Nat) := do
    let t0 ← IO.monoNanosNow
    let (o, apps) ← svc.reload path src (← IO.CancelToken.new)
    return (o, apps, ← ms t0)
  IO.println "each app's file, reloaded in the desktop's Lean three times:"
  let mut made : List (Lean.Name × App) := []
  for file in ["Clock", "Placeholder", "Repl", "Editor", "Boids"] do
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
  for path in ["LeanMachine/Desktop.lean", "Main.lean", "LeanMachine/Apps/Boids/Flock.lean"] do
    let (o, _, _) ← reloadNow path (← IO.FS.readFile (projectRoot / path))
    IO.println s!"  {path}: {o.show}"
  -- Boids' simulation is there, compiled, for the REPL too.
  let flockLine := "(Boids.Flock.demo.stepOn {} 100 100).map (·.position.x)"
  IO.println s!"  in the REPL, {flockLine}: {(← svc.eval flockLine none (← IO.CancelToken.new)).show}"
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
  -- Boids from the menu, and an editor on Boids.lean. `NEW ` typed at
  -- the start of its status line breaks a check of the file's, so
  -- nothing is reloaded; typed before the keys instead, and reloaded, it
  -- restarts the open flock with the new code, which frames step.
  let boidsSays (d : Desktop) : String :=
    let line := (((d.now.windows.find? (·.title == "Boids")).map (·.texts)).getD []).find?
      (·.contains " boids · ")
    (line.map fun s => " · ".intercalate ((s.splitOn " · ").take 3)).getD "?"
  let (bd, bruns) ← feed start {} [.tick ⟨10, 8, 30⟩, .menu 20 20, item 20 20 5,
    .menu 500 240, item 500 240 2]
  let (bd, bruns, _) ← settle bd bruns
  let (bd, bruns) ← feed bd bruns [.text "apps/boids.lean", dkey .enter]
  let (bd, bruns, _) ← settle bd bruns
  let bedWin := bd.now.focus
  let boidsSrc ← IO.FS.readFile (projectRoot / "LeanMachine/Apps/Boids.lean")
  let lines := boidsSrc.splitOn "\n"
  let statusLine := (lines.findIdx? (·.startsWith "  s!\"{s.flock.size} boids")).getD 0
  let keysAt := ((lines.getD statusLine "").splitOn "r random").head!.length
  let (bd, bruns) ← feed bd bruns ([.key .home { ctrl := true }] ++
    List.replicate statusLine (dkey .down) ++ List.replicate 5 (dkey .right) ++ [.text "NEW "])
  IO.println s!"Boids and an editor on it: windows {windows bd}; Boids says {boidsSays bd}"
  IO.println s!"  `NEW ` typed at the start of Boids' status line (line {statusLine + 1}), Ctrl+R:"
  let (bd, bruns) ← reloadOn bd bruns
  IO.println s!"    Boids says {boidsSays bd}; the editor: {(status bd bedWin).quote}"
  let (bd, bruns) ← feed bd bruns (List.replicate 4 (dkey .backspace) ++
    List.replicate (keysAt - 5) (dkey .right) ++ [.text "NEW "])
  IO.println s!"  moved to just before its keys, Ctrl+R:"
  let (bd, bruns) ← reloadOn bd bruns
  let bd' := [Event.frame 5000, .frame 5016, .frame 5032].foldl Desktop.step bd
  IO.println s!"    windows {windows bd}; Boids says {boidsSays bd}, after 3 frames \
    {boidsSays bd'}; the editor: {(status bd bedWin).quote}"
  render c bd'.view; shot c "reload-boids.png"
  let (bd, bruns) ← feed bd bruns [ctrlE 'o', ctrlE 'o', .text "boids/flock", dkey .enter]
  let (bd, bruns, _) ← settle bd bruns
  IO.println s!"  Flock.lean, Ctrl+R:"
  let (bd, _) ← reloadOn bd bruns
  IO.println s!"    the editor: {(status bd bedWin).quote}"
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
  -- Boids' step calls the compiled simulation either way; its view is
  -- the app's own code.
  let heard (a : App) (e : AppEvent) : App := ((a.step e).map (·.1)).getD a
  for (name, a) in [("compiled", boids), ("reloaded", madeApp ``boids)] do
    let mut a := (List.range 5).foldl (fun a i => heard a (.frame (1000 + 16 * i))) a
    let mut said := []
    for n in [150, 1000] do
      if n == 1000 then a := (List.replicate 17 (key .up)).foldl heard a
      let at_ := a
      let stepUs ← usPer 20 fun i => do
        if !(heard at_ (.frame (2000 + 16 * i))).animating then IO.println "?"
      let viewUs ← usPer 20 fun i => do
        if (at_.view (760 + (i % 2).toFloat) 544).texts.isEmpty then IO.println "?"
      said := said ++ [s!"at {n} boids a frame's step {stepUs} µs, the view {viewUs} µs"]
    IO.println s!"  a {name} Boids: {", ".intercalate said}"
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

end LeanMachine.Tests
