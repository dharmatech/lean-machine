# How it's built

The Lean code is one module per file in `LeanMachine/`, in the
`LeanMachine` namespace, with a thin `Main.lean` on top, and the tests
for `--test` in `Tests/`, a library of their own. An app can be
a folder of modules: Boids' are in `Apps/Boids/`, in `LeanMachine.Boids`. `Picture`, `Key`,
`App`, `Slider`, `Safepoint`, `Busy`, `Text`, the apps in `Apps/`, `World`,
`Desktop` and `View` are pure and import only each other. `Ambient` is what code in a
run can reach, for the REPL's Lean. Only `Host`, `Runs`, `Ambient` and
`Eval` call C (and `Safepoint`'s safepoints, pure C functions, and
`Main.lean`'s helpers for `--test`), only
`Eval` imports Lean, and only they, `Loop`, Boids' `Bench`, `Main.lean` and the tests touch `IO` (and
`Safepoint`'s `interrupted`, the error a stop becomes).

- `Picture.lean`: `Picture`, plain data: rectangles, circles, rings,
  lines, text at a point or aligned in a box, monospace text, a picture
  moved (`translate`) or cut to a box (`clip`), and groups. Cairo measures
  text for `textIn` when it draws, so a view can center text and stay
  pure. Monospace text (`mono`) goes the other way: Lean decides that each
  character takes `monoAdvance size` (0.6 em), and the shim puts every
  glyph in its cell, so a view knows where each character is, and where a
  cursor goes, without measuring. `Rect` is a box: a window's place on
  the screen, or a widget's in a window's body.
- `Key.lean`: `Key`, which key went down (a character key, in lower
  case, or Enter, the arrows, Home and the like), and `Mods`, the Ctrl,
  Shift and Alt held with it. `Key.show` writes one as "Ctrl+Shift+N".
  The desktop's own keys are Ctrl+Shift and a letter (`desktopKey`).
- `App.lean`: an `App` is a value with a title, a `view` at a given
  size, a `step` that returns the app an event makes and the requests
  it makes then (`none`: no change, nothing asked), and the `size` a new
  window gives it at first. A `Request` asks the loop to `run` work, a pure
  function `Unit → String`, or to `eval` a line of Lean in an `Env`,
  under a tag the app chooses, or to `stop` the run with a tag; the
  `Outcome` (a value; what Lean said, as `Said` messages, and the `Env`
  after the line; stopped, cleanly, with what Lean said first, or cut
  off; failed) comes back as an event with the tag and the milliseconds
  the run took. Files are requests too: `read` a file, `write` one,
  `list` the files under a folder, by paths from the desktop's own
  folder, with outcomes `read` (the text), `wrote` and `listed`.
  `reload` elaborates a file's text in the desktop's Lean; its outcome
  `reloaded` has what Lean said, as `Remark`s (a `Said` at a line and
  column), the Lean after the file, and the names of the apps that went
  to the world. An
  `Env`, a REPL's Lean, holds Lean's state, opaque
  here, so the pure modules don't import Lean, and pure functions
  over it that Eval.lean makes: `tokens`, a line's `Token`s (where each
  starts and stops, in characters, and its `TokenKind`), `tokensFrom`,
  the same for a line of a file that starts where a `Carry` says (in
  code, a comment so deep, or a string) and where the next line starts,
  and `complete`, what a name being typed could become.
  `App.asking` makes an app from a state of any type, a step and a view,
  and hides the state's type, so the desktop holds apps of every kind
  in one list, and can take the title from the state (`titleOf`), and
  whether it wants frames (`animating`);
  `App.of` makes one that never asks. `AppEvent` is an
  event in the app's own coordinates, a key with its modifiers, typed
  text, a turn of the wheel, a tick with the `TimeOfDay`, a run's
  outcome (`done`), the body's size (`resize`), heard as the window
  opens and whenever its size changes, or a frame (`frame`, with a
  monotonic clock's milliseconds), 60 a second while the app animates.
  `gripSize` is the corner of the body the desktop's grip covers.
- `Slider.lean`: `Slider`, a widget: a value from `lo` to `hi`, picked
  by dragging a knob along a track, evenly or on a cube
  (`Slider.Scale`), and whether the knob is held. An app keeps it in
  its state and gives it a box, the same to `heard`, the slider after
  a press, motion or release, and to `view`
  ([A slider is a value in a box the app gives it](widgets/slider.md)).
  `#guard`s check dragging it as it builds.
- `Safepoint.lean`: what compiled code calls where a stop may reach it.
  `poll x` is `x`, a safepoint in C. `safepoint` and `interruptNow` are
  the calls the REPL's Lean puts at the start of every function it
  compiles, and `interrupted` the `IO.Error.interrupted` an IO function
  returns there when it takes a stop.
- `Busy.lean`: compiled busy work, `n` million steps of it, that differ
  in where a stop can reach them: `alloc` allocates in every step,
  `polled` calls `poll` in every step, `spin` does neither.
- `Ambient.lean`: what code in a run can reach without being handed it:
  `world`, the world when the run was asked for, and `launch app`, which
  opens an app when the run ends. The run's guard keeps them for its
  thread. The REPL's Lean imports this module.
- `Apps/Clock.lean`: an analog face with the time in digits under it,
  after Schevana's `apps/clock.ss`. `clockFace` is a pure function of the
  time and the size; the app keeps the last tick's time and changes only
  when the second does.
- `Text.lean`: what the REPL and the editor share: `Line`, a line
  being edited, as the characters before the cursor (nearest first)
  and those after it; Tokyo Night's colours for tokens; rows of
  coloured runs (`runRows`), a `mono` each; and what Tab offers
  (`Offer`, `wordBefore`, `commonPrefix`), drawn in columns.
- `Apps/Editor.lean`: an editor of the desktop's Lean files. Its file
  is a `Buffer`: the lines above the cursor's (nearest first), the
  cursor's `Line`, and the lines below. Each line is `Lexed`: its text,
  its tokens, and where it and the next line start (`Carry`). An edit
  reads the cursor's line again (`Buffer.relex`), and the lines below
  only as far as they start differently now (`Buffer.again`). It asks
  for the desktop's Lean and the list of files as it opens, as the REPL
  asks for its Lean; opening and saving are `read` and `write`
  requests, under a tag for each kind, and so is Ctrl+R's `reload`.
  What Lean said at a reload goes on the lines it's about
  (`Lexed.said`, `Buffer.remark`), so the marks move with the lines;
  a line read again after an edit loses its own. The editor keeps the
  desktop's Lean (`base`) and the Lean it reads the file with (`env`),
  the Lean after the file once it's reloaded. The editor keeps the
  body's size from the last `resize` it heard (`editorSize` until then),
  and its `rows` and `cols` from that; `follow` keeps the cursor in view
  after a move or a resize. The title, from the state, is the file's
  name, with `•` when it has changes not saved.
- `Apps/Repl.lean`: a line editor over a transcript. A new REPL asks
  for the desktop's own Lean when it hears its first tick (an empty
  line evaluated there, under a tag of its own; again each second while
  it has none). Enter asks for the
  line to be evaluated in the REPL's `Env` (none at first: the
  desktop's own) and waits for one run at a time; a row under the
  transcript says it's running, and Ctrl+C asks for a stop. What Lean
  said goes in the transcript, output in green, warnings in amber,
  errors in red, with how long the run took, and the `Env` after the
  line becomes the REPL's. A stopped line says how it stopped:
  interrupted, through any `finally`, after what Lean said up to then,
  or cut off, past any `finally`. The line is a pair of lists, the
  characters before the cursor (nearest first) and those after it, so
  every edit is a cons or an uncons. Up and Down walk the history and
  come back to the line being typed. The transcript is a list, newest first, and the view
  cuts only the newest entries into rows, as many as fill the window;
  long lines wrap at the window's width in columns. Rows start at the
  top, and once they overflow the oldest go off the top, so the newest
  and the line being edited stay in view. Whatever changes the REPL,
  its Lean reads the line's tokens again (`relex`), and Enter keeps them
  with the line in the transcript, so the view only colours: each
  character takes its token's colour, and a row is drawn as runs of
  one colour, a `mono` each, at the column it starts in. Tab
  (`Repl.tab`) takes the name before the cursor (`wordBefore`, Lean's
  `isIdRest` and dots), unless the cursor is in a string or a comment,
  asks the `Env` what it could become, inserts as much as they all
  share, and keeps the rest as an `Offer` drawn under the line, in
  columns, without the namespace typed, until the line changes.
- `Apps/Placeholder.lean`: stands in for apps not written yet. A click
  drops a dot where it lands; it shows what was typed into it, the
  last key it heard, and its size beside the size it heard.
  `inspector` and `notes` are the menu's two.
- `Apps/Boids.lean`: Boids, Craig Reynolds' flocking, after the first
  port to Schevana ([Boids](boids/README.md)). Its `State` is the flock,
  its rules, the `StdGen` that scatters it and picks random rules, the
  body's size, whether it runs, and the frames' pace, smoothed. A frame
  steps the flock (`Flock.stepOn`) while it runs; R, D, S, Up, Down and
  Space change it; the app animates while it runs. The rules show
  beside the field, a `Row` each for the count and every `Setting`,
  with its label, a `Slider` made from the state (`State.slider`) and
  its value (`Setting.readout`); `sliderBox` places each for the view
  and for a press. The state keeps only which row is held
  (`State.held`), and `State.pointed` passes a press, motion or release
  to that row's slider and takes its value back (`State.setRow`). H
  hides the rules (`rulesShown`), and the field takes their room
  (`fieldWidth`). The view draws each
  boid as a dot and a line toward its heading, cut to the field, and a
  status line with the count and frames a second. `#guard`s check the
  keys and the pace as it builds, and again as it reloads. It reloads
  over the compiled simulation, which the REPLs' Lean imports
  ([A compiled simulation under a reloaded app](reloading/compiled-under-reloaded.md)).
- `Apps/Boids/`: Boids' simulation, and its bench. The modules import
  only Init and each other. The simulation's end with `#guard`s that
  run as they build, and the REPLs' Lean imports them, so they can't be
  reloaded.
  - `Vec.lean`: a vector in the plane, with `+`, `-`, `* k` and `/ k`
    through Lean's classes, `dot`, `length2`, `length`, `perp` and
    `mean`, all `@[inline]`; and `pi`.
  - `Random.lean`: `uniform lo hi`, a number picked with a `StdGen`,
    in `StateM`.
  - `Boid.lean`: `Boid`, a position and a velocity; what it `sees`, its
    `neighbors`, and each rule's raw push: `cohere`, `align`,
    `separate`, and Flake's `stepAside` and `backOff` for blockers.
  - `Rules.lean`: `Rules`, whose fields' defaults are the original
    settings (`{}`). `Setting` names each one, with its `range`, for
    random rules (`Rules.random`) and the rules' sliders; `Rules.set`
    keeps the speed limits from crossing.
  - `Flock.lean`: `Flock`, an array of boids. `Boid.steer` weighs and
    adds the pushes, and `Flock.step` steers every boid by the same
    flock. Then the screen's speed limits (`atLeast`, `atMost`) and
    `wrap`, `stepOn` (a frame), `scatter` and `resize`.
  - `Bench.lean`: `bench`, for `--bench`, times `stepOn` on
    `benchFlock`, a flock any language can make the same way, under the
    default rules and `heaviest`, and prints the bits of a sum of the
    flock after it ([How fast a step is](boids/step-speed.md),
    [The same bits as Chez](boids/same-bits-as-chez.md)). The REPLs'
    Lean doesn't import it.
- `World.lean`: windows, the pointer, the menu and events. Each window
  holds an app. `World.step : World → Event → World` moves, resizes,
  maximizes, restores, minimizes, raises, focuses and closes windows, passes ticks to every app,
  frames (`Event.frame`) to the apps that animate in windows that
  aren't minimized (`World.animating`: whether there are any), and passes other
  events, keys and text included, to the focused window's app, moved
  into the app's coordinates; a run's outcome (`Event.done`) goes to the
  window that asked for it, and an app a run launched (`Event.launch`)
  opens by that window. The wheel goes to the window under the pointer,
  focused or not. What apps ask for waits in the world's
  `outbox`, marked with the window, until the loop takes it
  (`takeAsked`). Ctrl+Shift+N opens the menu at the pointer.
  A window's place is a `Rect`. A press on a title or near an edge
  (`World.grabAt`, `Win.edgesAt`: up to `reach` outside the window, in
  its frame, near a corner, on the grip) starts a `Drag` of some
  `Edges`, all four for a title; each motion places the window at
  `Rect.drag` of where it started, no smaller than `minW` by `minH`
  when resizing, and only once the pointer has gone `dragSlop`.
  `World.place` is the one way a window changes place: its app hears
  `resize` when its body's size changes. A maximized window keeps where
  it was (`Win.restore`); `World.toggleMax` maximizes it to
  `desktopRect` or restores it, from the green box on its title
  (`Win.onMax`), a double click on the title (`Event.press`'s `clicks`)
  or Ctrl+Shift+M, and a drag makes it a normal window again, a title
  drag at its old size under the pointer (`Win.dragFrom`).
  A minimized window (`Win.minimized`, from the yellow box, `Win.onMin`,
  or Ctrl+Shift+H) keeps its place and `restore`, isn't drawn or found by
  a press (`World.visible`), and still hears ticks; `World.minimize`
  gives the focus to the frontmost window left, and `World.focusOn`
  brings one back, raised and focused. The taskbar is in front of the
  windows (`inBar`): `World.taskbar` lays out a button for each window,
  by id, and says whether the hint has room, guessing text widths
  (`approxW`); a press on a button (`World.buttonAt`) minimizes the
  focused window or focuses another (`World.pressButton`).
  The world holds a `catalog` of apps, the menu's items, each by the
  name of its declaration (`LeanMachine.clock`), and each window
  remembers the declaration its app came from (`Win.origin`; none for
  an app a REPL launched). `World.launch` opens an app in a new window,
  kept on the screen and told its size, then the time. A reload's apps
  (`Event.reload`) go through `World.reload`: each replaces the menu's
  item of its name, or is added, and the app of every window opened
  from it, but the window that asked; it starts afresh there
  (`World.fresh`), at the window's place and size. With no such window, it
  opens one beside the window that asked. `World.commits` says which
  events start a step undo can return to: a press that does something
  (not one that only closes the menu or misses the taskbar's buttons),
  a reload, and Ctrl+Shift+M and Ctrl+Shift+H.
- `Desktop.lean`: `Desktop` is the world now and every world before it;
  undo (Ctrl+Shift+Z) takes the previous one, apps' states included.
  The worlds kept for undo have empty outboxes, so undo never asks again.
  The start desktop opens the REPL, Clock, Inspector and Notes. Also `catalog`,
  what the menu opens (Clock, REPL, Editor, Inspector, Notes, Boids), each
  named with a ``` ``name ``` literal, which Lean checks is a declaration,
  and `start`, the desktop the program starts with, opened with
  `launch` as the menu would.
- `View.lean`: `Desktop.view` returns a `Picture`. Each app's view is
  moved to its window's body and cut to it, with the grip over its
  bottom right corner. The edges a drag resizes, or that a press where
  the pointer is would grab, are lit (`World.lit`). The boxes on a
  title a press where the pointer is would hit (`World.boxesLit`) are
  all in colour and show glyphs (`closeGlyph`, `minGlyph`, `maxGlyph`,
  `restoreGlyph`). Minimized windows
  aren't drawn. The taskbar (`World.barView`) draws each window's
  button (`Win.button`: a dot and the title, underlined if focused, lit
  under the pointer, dim if minimized), then the hint and the count of
  earlier worlds as one right-aligned text. The menu draws
  over everything, its item under the pointer lit.
- `Host.lean`: the calls into `shim.c` (a canvas and one window),
  `Event.decode` for the events the shim hands back as a `RawEvent` (a
  press brings SDL's count of clicks in a row; the
  right button is `Event.menu`; SDL's keycodes and modifier bits become a
  `Key` and `Mods`; the wheel brings the pointer's place and how far it
  turned), `Host.wake`, which any thread may call to end the
  loop's wait, `localTime` (through Lean's `Std.Time`), and `render`,
  the only code that draws.
- `Runs.lean`: the loop's side of requests. `Runs` is the runs going on:
  each a window and tag, a stop flag and a cancel token (`Live.stop`
  sets both), a Lean task with a dedicated thread that does the work
  inside a guard (runs.cpp) and calls `Services.wake` when it ends, and
  the apps it launched. `handle` starts and stops runs (a new run with a tag still going replaces it;
  a stop with nothing to stop is answered at once), evaluating through
  `Services.eval` and reloading through `Services.reload`, so this
  module needn't import Lean, and answers file
  requests at once (`fileOutcome`), from `Services.root`: a write goes
  beside the file and is renamed over it, and a listing walks the
  folder (`walkDir`) past hidden folders; `collect` turns
  runs that ended into `Event.done`, then `Event.reload` with the apps
  a reload made (a run ends with an `Ending`, its outcome and those
  apps), and `Event.launch`, and `keepFor`
  stops the runs of windows that are gone.
- `Eval.lean`: Lean in the desktop. `startBase` imports the REPLs' Lean
  (`replImports`: `Init`, `LeanMachine.Ambient`, `LeanMachine.Text`,
  `LeanMachine.Slider` and Boids' simulation,
  `LeanMachine.Apps.Boids.Flock`; not the apps) on a thread of its
  own as the desktop starts, and opens `LeanMachine`. `eval` takes a
  line, wraps it in `#eval` if it parses as a term, and elaborates it on
  the calling thread with `runCommands`, its own loop over Lean's
  parser and `elabCommandTopLevel`, with the run's cancel token; once
  it's set, no more commands are elaborated and the line has stopped,
  cleanly. An `Env` holds Lean's `Command.State`, the environment and
  the scopes left open, with `lexLine` and `completeIn` over it.
  `lexLine` runs Lean's tokenizer (`tokenFn`) along the line with the
  environment's token table, and calls an identifier a constant if
  `resolveGlobalName` finds one for it from the line's scope; what lies
  between tokens and isn't blank is a comment. `completeIn` looks the
  name's last part up among the names in the namespace its other parts
  name, from the current namespace, the ones around it, the root and
  the open ones, plus what the REPL defined and, with no namespace,
  keywords; theorems come after the rest. The names imported are
  indexed by namespace once, in a task of its own after the import
  (`nameIndex`), and every REPL shares the index. The REPLs' Lean compiles with one pass more than
  Lean's own (`withSafepoints`): `safepointsPass`, at the end of the
  compiler's impure phase, starts every function at a safepoint, and an
  IO function (`returnsIO`) at one that can return `interrupted`.
  `lexFrom` is `tokensFrom`: a comment or string the line before left
  open is read to its end by hand (`commentEnd`, `stringEnd`), the rest
  by `lexLine`, and where the tokenizer gave up on a comment or string
  this line leaves open (`openAt`), that's coloured as what it is and
  carried to the next line. `projectRoot` is the desktop's own folder,
  noted as this module compiles (`getFileName`: Lake passes Lean full
  paths). `reload` refuses a file whose module (`moduleOf` its path)
  the REPLs' Lean imported, parses its header, checks that everything it
  imports is in the REPLs' Lean, and elaborates the rest of the file
  there, from a fresh `Command.State` (the root namespace, nothing
  open), with the run's cancel token; with no error, `appsIn` finds the
  constants of type `App` it added (`constants.map₂`) and `evalConst`
  makes each a value. The editor gets the Lean after the file, with
  `LeanMachine` open, as the REPLs' Lean has it.
- `Loop.lean`: the loop's parts that don't draw. `feed` steps the
  desktop through events and hands what its apps ask to `Runs`, with
  the world they asked in; a request answered at once is stepped
  through after the rest. Frames are `framePeriod` apart, and
  `nextFrameAfter` says when the next is due. The loop and `--test`
  both drive the desktop with `feed`.
- `Main.lean`: `run`, the loop. Each pass waits for events, but
  not past 100 ms or the next second, nor, while an app animates, past
  the next frame (a run that ends wakes it), applies
  them with `feed`, then the outcomes of runs that ended, stops the runs of windows
  that are gone, ticks with the time, gives a frame if one is due
  (`nextFrameAfter`), and draws. Also the tests for `--test` that
  haven't moved to `Tests/` yet: `test`, `testReload`, `testRuns` and
  `testMasking`; and `main`, which runs
  them for `--test`, and `Boids.bench` (`Apps/Boids/Bench.lean`) for
  `--bench`.
- `Tests/`: the tests `--test` runs, in `LeanMachine.Tests`, moving
  here from `Main.lean` one at a time. Nothing in `LeanMachine/`
  imports them.
  - `Show.lean`: how the tests print what they find: `Outcome.show`,
    `Event.showDone` and the like for what came back from runs, tokens
    and the editor's lines (`showTokens`, `showLexed`), and windows'
    edges and places (`Edges.show`, `showRect`).
  - `Kit.lean`: what the tests share. `settle` waits for every run to
    end and tells the desktop how each did; `stepNow` steps the desktop
    and settles; `answerNow` steps an app's state and answers what it
    asks at once, on the test's thread (`hearNow` for a REPL, `appNow`
    for any app); `steps` steps the desktop with nothing done for it.
    Then what pictures and windows show (`Picture.texts`, `says`,
    `rectOf`), `dragBy`, `undoKey`, `shot` (a picture of the canvas in
    `.lake/test/`), `usPer` and `rssMB`.
  - `Frames.lean`: `testFrames`: a spinner, an app that animates,
    opened, minimized, undone, and made in a REPL.
  - `Boids.lean`: `testBoids`: Boids from the menu, its rules' sliders,
    H, Space and minimizing, and what a frame costs at 150 boids and
    at 1000.
  - `Slider.lean`: `testSlider`: `sizer`, the slider of
    [the slider exploration](../explore/slider.md) in a window, dragged
    and undone, then the same slider made in a REPL (`sliderLines`).
  - `Resize.lean`: `testResize`: windows resized by an edge, a corner
    and the grip, an editor told its sizes, and a reload that keeps a
    window's size ([Resizing](world/resizing.md)).
  - `Maximize.lean`: `testMaximize`: by the box on a title, a double
    click and Ctrl+Shift+M, each undone, and a maximized window dragged
    ([Maximizing](world/maximizing.md)).
  - `Minimize.lean`: `testMinimize`: windows minimized and brought
    back, the taskbar's buttons, and the boxes on a title
    ([Minimizing](world/minimizing.md)).
  - `Highlight.lean`: `testLean`: the tokens the REPL's Lean reads in a
    line, what Tab makes of names, on a REPL alone and on the desktop,
    and what each costs ([Highlighting](highlighting/README.md)).
  - `Editor.lean`: `testEditor`: a file's lines read with what the
    line before left open, an editor alone on a scratch file, then on
    the desktop with Clock.lean, and what it costs
    ([The editor](editor/README.md)).
- `shim.c`: Cairo draws into an image in memory, and SDL3 shows it in
  one window and hands back events, text input included, the wheel,
  and a wake (an SDL user event). No GPU in the design.
- `runs.cpp`: stopping a run. A run's thread is inside a guard
  (`sv_guarded` for a pure function, `sv_guarded_io` for an IO action)
  while it works; safepoints check its stop flag (a thread-local
  pointer to it). A raised flag is first offered to IO code compiled in
  the REPL (`sv_interrupt_now`), for 50 ms; then a safepoint throws a
  C++ exception that the guard catches (it cuts the run off). Code that
  took the offer gets 500 ms to finish before it too is cut off. The
  safepoints are `poll`, the ones the REPL compiles in, every small
  allocation (the linker sends Lean's `lean_alloc_small_object_core`
  through a wrapper here), and the end of a masked region: wrappers
  around `Ref.take` and `Ref.put` and the mutexes' lock and unlock count
  what the thread holds, and no run is cut off while it holds any. A
  wrapped `IO.sleep` ends when its run is asked to stop. The guard also
  keeps the run's ambient in a thread-local, for `sv_ambient`.
- `lakefile.lean` builds the `LeanMachine` and `Tests` libraries and `Main.lean`,
  compiles `shim.c` with `cc` and `runs.cpp` with `c++`, and links them
  into `desktop` with Lean's interpreter (`supportInterpreter`) and a
  `-Wl,--wrap=` for each runtime function runs.cpp wraps.

[↑ Design](README.md)
