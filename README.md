# Lean Machine

A desktop whose world is a value, in Lean 4. Nothing in it is mutated:
an event makes a new world, the view turns a world into a picture, and
one loop at the edge does the I/O.

It grew out of conversations about [Schevana](https://github.com/paveluv/Schevana)
(a Lisp Machine-style desktop in Chez Scheme) on 2026-11-04 and 2026-11-17:
what would such a desktop be in a language with static types, methods by
dot notation, and no mutation? The name is a working title.

## Run

```sh
lake build                 # writes .lake/build/bin/desktop
.lake/build/bin/desktop
```

`lake exe desktop` does both: it builds if anything changed, then runs
the desktop with any arguments that follow.

Right-click anywhere, or press Ctrl+Shift+N, for a menu of apps; choose
one to open it in a new window where the menu was. Esc closes the menu,
and so does a click off it. Drag a window by its title, click one to
raise it, click the box on a title to close it, Ctrl+Shift+Z to undo, Esc
to quit. Clock is a clock.

The REPL evaluates Lean in the desktop's own process: Init and the
desktop's modules, with `LeanMachine` open. A line is Lean commands
(`def sq (n : Nat) := n * n`, `#eval`, `namespace`, `open`) or a term,
evaluated as `#eval` would (`sq 12`); what Lean says comes back under
it, errors in red. Each line runs on a thread of its own, so the desktop
goes on drawing and taking events, and the line can be edited
meanwhile; Ctrl+C stops a run (or clears the line when nothing runs).
Each REPL has its own Lean, kept in its state, so undo takes back
definitions too. In a REPL, `world` is the desktop as it was when Enter
was pressed (`(·.windows.map (·.title)) <$> world`), and `launch app`
opens an app made there in a new window. `Busy.alloc 100`,
`Busy.polled 1000` and `Busy.spin 1000` are compiled busy work, a few
seconds each; the first two stop at Ctrl+C, `spin` doesn't and
finishes. Every function the REPL compiles starts at a safepoint, so
loops defined there stop too (`set_option leanMachine.safepoints false
in def …` leaves the safepoints out). A stop that reaches IO code
defined in the REPL comes as `IO.Error.interrupted`, so `try`/`finally`
run, and the REPL says "interrupted after …"; anything else is cut off
at a safepoint, past any `finally` ("cut off after …"). Click in the
REPL and type; Left, Right, Home, End, Backspace
and Delete edit the line, and Up and Down go back and forth through
earlier lines. The line, and every line entered, is coloured by the
tokens the REPL's Lean reads in it: keywords purple, symbols cyan,
names of constants blue (`sq` turns blue once it's defined), other
identifiers pale, numbers orange, strings green, comments gray, and red
from where Lean's tokenizer gives up (`"unterminated`). Tab completes the
name before the cursor from the names that REPL's Lean has, its own
definitions and open namespaces included (`Busy.al` → `Busy.alloc`,
`monoAdv` → `monoAdvance`), as far as every name it could become
agrees, and shows them under the line when there's more than one
(`Picture.` shows its ten constructors).
The Editor edits the desktop's own Lean files. It opens on a list of
them: type part of a path to narrow it (`apps/cl`), Up and Down to
choose, Enter or a click to open one. In a file, the arrows, Home, End,
PageUp, PageDown, Ctrl+Home and Ctrl+End move the cursor, a click puts
it where it lands, and the wheel scrolls; Backspace and Delete join
lines at their ends, and Enter starts the new line as far in as the
last, two more after `:=`, `do`, `where`, `=>`, `by`, `then` or
`else`. The file is coloured
as the REPL colours a line, with comments and strings that span lines
(`/- … -/`, the module's doc comment) coloured as one. Tab completes the
name before the cursor from the desktop's Lean (`TimeOfDay.` offers its
fields), or indents. Ctrl+S saves (the title's `•` says there are
changes not saved), Ctrl+O goes back to the list (twice, if there are
changes not saved). Esc still quits the desktop, changes and all.
Inspector and Notes are placeholders: click in one to drop a dot, or
type into it to see the text and the last key, with its modifiers, that
it heard. The bar at the bottom counts
the earlier worlds that undo can return to.

```sh
.lake/build/bin/desktop --test        # the pure world, driven by a script of events
.lake/build/bin/desktop --frames 20   # stops after 20 frames
SDL_VIDEO_DRIVER=dummy .lake/build/bin/desktop --frames 20   # the same, with no display
```

`--test` writes `after-script.png`, `after-undo.png`, `menu.png` (the
menu open) and `repl.png` (the REPL after a script of typing, editing
and history) in the current directory, and `sampler.png`, one of each
kind of picture. It also prints the REPL's line, history and first
entries after that script, and what `Event.decode` makes of a few
events as the shim hands them back, and the monospace font's own
advance beside `monoAdvance`'s. It prints the tokens the REPL's Lean
reads in two lines, and what Tab makes of names with one completion
and with several, and writes `repl-highlight.png` (lines of every kind
of token, and a line being edited), `repl-complete.png` (`Picture.`
and Tab) and `repl-complete-many.png` (`List.ma`, 236 names). It
times reading a line's tokens, a keystroke, Lean's parser on the same
line, Tab on a few names, making the index of names, and drawing a
REPL window full of highlighted lines against the same lines in one
colour. Then it evaluates Lean on real threads
through the desktop's REPL and the loop's `feed`, and prints what came
back from each line: definitions, a type error, a namespace across
lines, `world`, printed output. Busy work and loops defined in the REPL
are stopped by Ctrl+C after 300 ms (`repl-running.png` is the REPL with
one going, `repl-runs.png` after them all). It times loops defined in
the REPL with safepoints and without, then stops lines that Lean sees
the stop in, or doesn't: a `try … finally`, pure code inside one, a
loop that catches the stop and goes on, `IO.sleep`, a loop without
safepoints, a slow `#reduce` (`repl-interrupt.png`). An app made in the
REPL is launched and clicked (`repl-launch.png`); an undo takes a
definition back (`repl-undo.png`); two REPLs evaluate at once. It also
prints a frame's time with a run going, what closing the REPL did to
its run, and the RSS after 50 runs were stopped. Last, it cuts off
compiled code ten times in the middle of `Ref.modify`, and ten times
while it holds a mutex, with masking off and then on, and says how
often the ref was left taken or the mutex locked.

Between the REPL's highlighting and its runs, `--test` tries the
editor. It prints the tokens of six lines of a file that leave a
comment, a nested comment, a string and a doc comment open for the next
line. An editor on its own, its requests answered at once, opens a
scratch copy in `.lake/editor-test/`: it prints the file's lines, where
each starts and what it leaves open, after `/- ` is typed at the top and
after ` -/` closes it three lines down, after Enter and Backspace join
and split lines, then saves (Ctrl+S) and prints what's on disk, and
leaves with Ctrl+O, once with changes and then again. On the desktop it
opens the Editor from the menu (`editor-files.png`), opens Clock.lean by
typing `apps/cl`, and Tab after `TimeOfDay.` (`editor-complete.png`),
then opens a comment at the top and turns the wheel
(`editor-comment.png`). A press and the wheel move the cursor and the
view of Editor.lean. Last, it times reading every line of Repl.lean, a
keystroke in the middle of it, opening a comment at its top and closing
it again, Down, and drawing an editor full of code.

Needs Lean 4.36 through elan (`lean-toolchain` pins it), Cairo, SDL3's
shared library, and a C++ compiler (`c++`). SDL3's headers
(`libsdl3-dev`) are not needed. The desktop reads the .olean files of
the Lean it was built with when it runs, so that toolchain must stay
installed.

## How it's built

The Lean code is one module per file in `LeanMachine/`, in the
`LeanMachine` namespace, with a thin `Main.lean` on top. `Picture`, `Key`,
`App`, `Safepoint`, `Busy`, `Text`, the apps in `Apps/`, `World`,
`Desktop` and `View` are pure and import only each other. `Ambient` is what code in a
run can reach, for the REPL's Lean. Only `Host`, `Runs`, `Ambient` and
`Eval` call C (and `Safepoint`'s safepoints, pure C functions, and
`Main.lean`'s helpers for `--test`), only
`Eval` imports Lean, and only they and `Main.lean` touch `IO` (and
`Safepoint`'s `interrupted`, the error a stop becomes).

- `Picture.lean`: `Picture`, plain data: rectangles, circles, rings,
  lines, text at a point or aligned in a box, monospace text, a picture
  moved (`translate`) or cut to a box (`clip`), and groups. Cairo measures
  text for `textIn` when it draws, so a view can center text and stay
  pure. Monospace text (`mono`) goes the other way: Lean decides that each
  character takes `monoAdvance size` (0.6 em), and the shim puts every
  glyph in its cell, so a view knows where each character is, and where a
  cursor goes, without measuring.
- `Key.lean`: `Key`, which key went down (a character key, in lower
  case, or Enter, the arrows, Home and the like), and `Mods`, the Ctrl,
  Shift and Alt held with it. `Key.show` writes one as "Ctrl+Shift+N".
  The desktop's own keys are Ctrl+Shift and a letter (`desktopKey`).
- `App.lean`: an `App` is a value with a title, a `view` at a given
  size, a `step` that returns the app an event makes and the requests
  it makes then (`none`: no change, nothing asked), and the `size` a new
  window gives it. A `Request` asks the loop to `run` work, a pure
  function `Unit → String`, or to `eval` a line of Lean in an `Env`,
  under a tag the app chooses, or to `stop` the run with a tag; the
  `Outcome` (a value; what Lean said, as `Said` messages, and the `Env`
  after the line; stopped, cleanly, with what Lean said first, or cut
  off; failed) comes back as an event with the tag and the milliseconds
  the run took. Files are requests too: `read` a file, `write` one,
  `list` the files under a folder, by paths from the desktop's own
  folder, with outcomes `read` (the text), `wrote` and `listed`. An
  `Env`, a REPL's Lean, holds Lean's state, opaque
  here, so the pure modules don't import Lean, and pure functions
  over it that Eval.lean makes: `tokens`, a line's `Token`s (where each
  starts and stops, in characters, and its `TokenKind`), `tokensFrom`,
  the same for a line of a file that starts where a `Carry` says (in
  code, a comment so deep, or a string) and where the next line starts,
  and `complete`, what a name being typed could become.
  `App.asking` makes an app from a state of any type, a step and a view,
  and hides the state's type, so the desktop holds apps of every kind
  in one list, and can take the title from the state (`titleOf`);
  `App.of` makes one that never asks. `AppEvent` is an
  event in the app's own coordinates, a key with its modifiers, typed
  text, a turn of the wheel, a tick with the `TimeOfDay`, or a run's
  outcome (`done`).
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
  requests, under a tag for each kind. `follow` keeps the cursor in
  view; the step can't know the window's size, so it uses the size the
  editor asks for (`editorSize`), as windows don't change size yet. The
  title, from the state, is the file's name, with `•` when it has
  changes not saved.
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
  drops a dot where it lands; it shows what was typed into it and the
  last key it heard.
- `World.lean`: windows, the pointer, the menu and events. Each window
  holds an app. `World.step : World → Event → World` drags, raises,
  focuses and closes windows, passes ticks to every app, and passes other
  events, keys and text included, to the focused window's app, moved
  into the app's coordinates; a run's outcome (`Event.done`) goes to the
  window that asked for it, and an app a run launched (`Event.launch`)
  opens by that window. The wheel goes to the window under the pointer,
  focused or not. What apps ask for waits in the world's
  `outbox`, marked with the window, until the loop takes it
  (`takeAsked`). Ctrl+Shift+N opens the menu at the pointer.
  The world holds a `catalog` of apps, the menu's items, but knows none
  of them by name. `World.launch` opens an app in a new window, kept on
  the screen and told the time first. `World.commits` says which events
  start a step undo can return to: a press that does something.
- `Desktop.lean`: `Desktop` is the world now and every world before it;
  undo (Ctrl+Shift+Z) takes the previous one, apps' states included.
  The worlds kept for undo have empty outboxes, so undo never asks again.
  The start desktop opens the REPL, Clock, Inspector and Notes. Also `catalog`,
  what the menu opens (Clock, REPL, Editor, Inspector, Notes), and `start`, the desktop the program starts with,
  opened with `launch` as the menu would.
- `View.lean`: `Desktop.view` returns a `Picture`. Each app's view is
  moved to its window's body and cut to it. The menu draws over
  everything, its item under the pointer lit.
- `Host.lean`: the calls into `shim.c` (a canvas and one window),
  `Event.decode` for the events the shim hands back as a `RawEvent` (the
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
  `Services.eval`, so this module needn't import Lean, and answers file
  requests at once (`fileOutcome`), from `Services.root`: a write goes
  beside the file and is renamed over it, and a listing walks the
  folder (`walkDir`) past hidden folders; `collect` turns
  runs that ended into `Event.done` and `Event.launch`, and `keepFor`
  stops the runs of windows that are gone.
- `Eval.lean`: Lean in the desktop. `startBase` imports the REPLs' Lean
  (`Init`, `LeanMachine.View`, `LeanMachine.Ambient`) on a thread of its
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
  paths).
- `Main.lean`: `run`, the loop. `feed` steps the desktop through events
  and hands what its apps ask to `Runs`, with the world they asked in. Each pass waits for events, but
  not past 100 ms or the next second (a run that ends wakes it), applies
  them, then the outcomes of runs that ended, stops the runs of windows
  that are gone, ticks with the time, and draws. Also `test`,
  `testLean`, `testEditor`, `testRuns` and `testMasking` for `--test`
  (`answerNow` steps an app's state and answers what it asks at once),
  and `main`.
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
- `lakefile.lean` builds the `LeanMachine` library and `Main.lean`,
  compiles `shim.c` with `cc` and `runs.cpp` with `c++`, and links them
  into `desktop` with Lean's interpreter (`supportInterpreter`) and a
  `-Wl,--wrap=` for each runtime function runs.cpp wraps.

## Findings so far

- **Speed.** Cairo redraws the whole 1280×800 screen, 10 windows with
  titles, in 0.56 ms (Cairo alone, before SDL). Redrawing everything every
  frame is fine; no damage tracking yet.
- **Lean's main thread.** Lean 4.36 runs `main` on a thread of its own.
  SDL wants its window and events on the process's main thread, and the
  GTK plugin that draws a window's title bar on GNOME/Wayland won't start
  anywhere else (`Failed to load plugin 'libdecor-gtk.so': failed to init`,
  then no title bar). `LEAN_MAIN_USE_THREAD=0` keeps `main` on the main
  thread; only `0` does, not `false` or `1`. `shim.c` sets it in a
  constructor that runs before `main`.
- **Linking.** Lean's toolchain links against its own C library. Name a
  system library by path with `-Wl,--allow-shlib-undefined`; an `-L` to
  `/usr/lib/x86_64-linux-gnu` pulls in the system's start files and fails.
  That C library is old: no `gettid` (use `syscall(SYS_gettid)`).
- **Compiling C.** `leanc`'s bundled clang has no system headers
  (`math.h`), so the lakefile compiles `shim.c` with the system `cc`.
- **SDL3 without headers.** `shim.c` declares the twelve SDL calls it
  uses and reads event fields at the offsets Schevana v0 reads: a key's
  code at 28 and modifiers at 32, a text event's string at 24.
- **Text out of the shim.** SDL sends text only after
  `SDL_StartTextInput(window)`, as a pointer to a string it frees at the
  next poll. `Host.event` returns a `RawEvent`, a structure of a
  `FloatArray` and a `String`; Lean lays out a structure of two boxed
  fields as a plain two-field constructor, so C builds it with
  `lean_alloc_ctor(0, 2, 0)` and copies the text into it. One call per
  event, and no text waiting in a C global.
- **Keys and text are separate events.** A key brings SDL's keycode and
  modifiers; typing brings text, as the layout and any input method made
  it ("é", "N"). Apps insert text and act on keys. Text typed with Ctrl
  held is dropped (the shim sends the modifiers along with it), so
  Ctrl+Shift+N doesn't also type an N. SDL may give a letter key in upper
  case when Shift is down, so `Key.ofSDL` lowers it.
- **Ctrl+Shift+U belongs to IBus.** On GNOME, IBus takes Ctrl+Shift+U for
  typing a character by its code point, before an app sees it, so the
  desktop's undo is Ctrl+Shift+Z. Desktop keys follow Schevana's
  Ctrl+Shift, which leaves plain letters, Shift and Ctrl alone (Ctrl+C,
  say) to apps.
- **Monospace on Lean's grid.** A pure view can't ask Cairo how wide text
  is. For monospace text it doesn't have to: Lean fixes the advance at
  0.6 em and the shim places glyph i at x + i·advance with
  `cairo_show_glyphs` (Cairo's toy text API makes one glyph per
  character). The font picked for "Monospace" here, DejaVu Sans Mono,
  measures 0.602 em, so glyphs sit in their cells with no visible drift,
  and a cursor or a click maps to a column by arithmetic.
- **Bindings.** There are no Lean bindings for Cairo. There are some for
  SDL3 ([ValorZard](https://reservoir.lean-lang.org/@ValorZard/SDL3)) and
  raylib ([Raylib.lean](https://github.com/KislyjKisel/Raylib.lean)), but a
  `Picture` needs only a few coarse C calls, so owning them is cheap.
- **An app can't always return an app.** `step : AppEvent → App` type
  checks, but the type has no values: building one needs an `App`
  already. `step` returns `Option (App × List Request)`, and `none` ends
  the chain. An app that keeps state refers to itself, so it can't be
  total; `App.asking` is the one `partial` definition, and apps passed
  to it stay total.
- **Time.** Lean's `Std.Time` reads the local time (`PlainTime.now`) in
  about 80 µs, time zone included, so the loop calls it every frame and
  no C is needed. Time comes into the pure world only as a tick event.
  Undo puts back an earlier world, clocks included, but the loop ticks
  before every frame, so a stale time is never drawn.
- **Lists over arrays in app state.** An app's state lives on in the
  worlds undo keeps, so an `Array` push there copies the whole array
  whenever an earlier world still holds it (Lean updates an array in
  place only when nothing else holds it). The REPL's
  transcript and history are lists, newest first: adding is a cons that
  shares the rest with every earlier world.
- **Commands take words.** Lean's built-in commands reserve their names
  everywhere: `def recall` doesn't parse, because `recall` is a command
  (it restates a declaration). A REPL user will hit the same thing;
  `«recall»` gets around it.
- **Apps are opaque.** The state inside an app is in closures, so nothing
  outside it, an Inspector included, can look at it. An app could later
  offer a description of itself.
- **Opening an app is placing a value.** The menu's items are `App`
  values, and choosing one puts that value in a new window. There is no
  class to instantiate: every Clock starts as the same value and goes
  its own way as it hears ticks.
- **Work as a pure function.** A run is a `Unit → String` an app
  builds in its step; the loop calls it on another thread. Lean makes
  that safe without asking anything of the app: a closure handed to a
  task is marked multi-threaded (`lean_mark_mt`), with everything it
  reaches, and from then on its reference counts change atomically. So
  a closure that captures something big pays to mark all of it, and the
  world's objects it shares stay atomic for good. Because an app only
  asks, `--test` can also answer a REPL at once on its own thread
  (`hearNow`), with no runs at all.
- **Requests in the world.** Apps don't do I/O; they ask, and the world
  keeps what they asked in an outbox, marked with the window, until the
  loop takes it after each event. The outcome comes back as one more
  event, to the window that asked. Results can't carry an `App`: an
  `AppEvent` holding an `App` would put `App` to the left of an arrow in
  its own definition (`step : AppEvent → …`), which Lean rejects as not
  strictly positive. An app a REPL made goes to the world instead, as
  `Event.launch`.
- **Threads.** `IO.asTask (prio := .dedicated)` gives each run a thread
  of its own, outside Lean's pool of workers: from asking to the end of
  a run that does nothing takes about 150 µs. The loop waits on SDL's
  queue, not on Lean tasks (Lean's `IO.waitAny` can't wait on SDL too),
  so a run's task has a continuation (`IO.mapTask (sync := true)`, run
  on the finishing thread once the task has its value) that pushes an
  SDL user event; `SDL_PushEvent` may be called from any thread. With
  it, the outcome of a run that does nothing is seen 1.2 ms after Enter;
  without it, the loop sleeps out its 100 ms wait first. A frame takes
  the same 1.1 ms with a run allocating flat out on another thread:
  Lean's allocator keeps a heap per thread.
- **Stopping a run.** Lean has no way to stop a thread: `IO.cancel` only
  sets a flag that code must check (`IO.checkCanceled`). Here a run's
  thread raises a C++ exception at a safepoint once its flag is up, and
  `sv_guarded` catches it at the run's edge, with no change to Lean. The
  linker's `--wrap` makes every small allocation a safepoint, from Lean
  code compiled anywhere (`Init` and `Std` included, as they're linked
  statically) and from Lean's C++ runtime, whose locks are released as
  the exception passes; `poll` is the other. `alloc` and `poll` stop within a
  millisecond of Ctrl+C (50 ms in the REPL, which offers the stop to
  Lean code first: see below); `spin`, a compiled loop on small `Nat`s
  that neither allocates nor polls, can't be stopped and runs to its
  end. Lean's compiler would have to put polls in the loops it compiles
  for that. Unwinding skips the Lean code it leaves, so what that code
  held is never freed, but a stop in a loop that drops what it makes
  leaks little: RSS stayed at 23 MB over 50 stops. No Lean `finally`
  runs on the way, as the exception isn't Lean's; stops that Lean sees
  are below.
- **Exiting with a run going.** Lean's `main` calls
  `lean_finalize_task_manager` on its way out, but that doesn't wait for
  dedicated threads: quitting with a `spin` going exits at once. The
  loop raises every run's flag first anyway.
- **Undo and work in flight.** The world is a value, but a run going on
  is an effect, and undo can't take it back (what a REPL defined, it
  can: see below). Undo to a world from before
  Enter leaves a run whose outcome the REPL won't wait for (it ignores
  outcomes with other tags, and a new run with the same tag replaces
  the old). Undo to a world that waited for a run whose outcome came
  later brings back a REPL that waits for nothing; Ctrl+C gets it out,
  as a stop with nothing to stop is answered at once. Closing a window,
  or undoing to before it opened, stops its runs: the loop compares its
  runs with the windows after each pass.
- **Linking Lean.** With Lean's interpreter linked in, the executable
  goes from 6 MB to 239 MB, and a clean build takes 6.5 s. A headless
  run of one frame still takes 0.23 s; importing the REPLs' Lean (Init
  and the desktop's modules) takes 125 ms, on a thread of its own, and
  RSS goes to 485 MB. Importing all of `Lean` would take 1.6 GB, so the
  REPL's Lean doesn't, and neither may any module it imports: that's
  why `Env` is opaque in `App.lean` and cast (`unsafeCast`) to Lean's
  `Command.State` only in `Eval.lean`. The .olean files of the Lean the
  desktop was built with are read at run time, so `Eval.lean` notes that
  Lean's place as it compiles (`getBuildDir` in a term elaborator) and
  passes it to `initSearchPath`; the desktop's own .olean files are
  found next to the executable.
- **Elaborating on the run's thread.** `Lean.Elab.process` elaborates
  each command in a task on Lean's pool of threads (the language
  server's incremental processor), where the run's stop flag and
  ambient aren't. The older `Frontend.processCommands` stays on the
  calling thread but loses every message: `elabCommandTopLevel` clears
  the log as each command starts, the end of input included. So
  `Eval.lean` runs its own loop of `Parser.parseCommand` and
  `elabCommandTopLevel`, taking each command's messages, with
  `Elab.async` off. `#eval` gathers what the code printed itself
  (`withIsolatedStreams`, by thread). A line that parses as a term is
  wrapped in `#eval`. Simple lines take 1 to 12 ms.
- **A REPL's Lean is a value.** Lean's `Command.State`, the environment
  and the open scopes, is persistent data, so the REPL keeps it in its
  state: a `namespace` or `open` lasts across lines, each REPL has its
  own definitions, two REPLs evaluate at once without touching each
  other, and undo takes a definition back with the rest of the world.
  A stopped line leaves the REPL's Lean as it was.
- **Dynamic scope by hand.** Lean has no thread-local or dynamically
  scoped values (Scheme's `parameterize`), so `world` and `launch` reach
  their run through a C++ thread-local the guard sets. Code that starts
  tasks of its own leaves the ambient, and the stop flag, behind.
- **Stopping evaluation.** Compiled code called from the REPL stops as
  it did before: `Busy.alloc` and `Busy.polled` within a millisecond
  (50 ms now that a stop is offered to Lean code first, below).
  So does a loop defined in the REPL that allocates, which the
  interpreter runs; one that only does arithmetic on small `Nat`s
  (about 250 ns a step interpreted, 60 times compiled code) couldn't be
  stopped, like `Busy.spin`, until the REPL put safepoints in what it
  compiles (below). A stop that comes while a loop without safepoints
  runs (`Busy.spin`, or `quietRaw` below) takes effect at the first
  allocation after it, so the run reports that it stopped after the
  loop's whole time. RSS grew 1 to 2 MB over 50 stopped evaluations.
- **Safepoints in what the REPL compiles.** Lean 4.36's compiler (LCNF)
  runs a list of passes kept in the environment, as an extension's state
  (`passManagerExt`), so that a module can add passes for the modules
  that import it (`@[cpass]`). The REPLs' Lean gets one more pass by
  changing that state once it's imported: the pass is compiled into the
  desktop, so the REPLs' Lean needn't import Lean for it, and nothing
  else compiles with it. It runs at the end of the impure phase, after
  boxing and reference counting, so that nothing later drops or moves
  what it adds, and starts every function with `safepoint 0`, those of
  `#eval` included. Loops in what Lean compiles are recursive functions
  (join points don't loop), so a safepoint at the start of every
  function reaches every loop the REPL compiles, closures and
  specializations of library loops included: `quiet 4000000 0` stops 50
  ms after Ctrl+C. Two things to know when writing such a pass: in the
  impure phase a `cases` is named by its discriminant's type in the
  machine (`UInt8` for a `Bool`; naming it `Bool` panics in
  `nameToIRType`), and an impure signature no longer says whether a
  function is IO, so `returnsIO` asks the declaration the mono phase
  saved (`… → lcVoid → EST.Out IO.Error …`).
- **What safepoints cost.** About 50 ns a call of a function defined in
  the REPL: that's what the interpreter takes to call compiled code,
  whether through the `@[noinline]` wrapper or the extern itself (its
  `_boxed` version, which Lean makes for externs with scalar
  arguments). On loops that do nothing else, 2 million steps: `quiet`
  588 ms with safepoints, 486 ms without (+21%); an empty IO loop 389
  and 283 ms (+37%). Code that does more in a call pays less, and
  compiled code pays nothing. `set_option leanMachine.safepoints false
  in def …` leaves them out of a definition (`register_option` in a
  compiled module registers the option as the desktop starts).
- **The world is gone from IO.** In Lean 4.36, `IO α` is `EST IO.Error
  IO.RealWorld α`: a function from an erased world (`Void`) to an
  `EST.Out`, `ok` or `error` with one field each. Externs take no world
  argument, and `BaseIO` and `ST` results aren't boxed at all. So an IO
  function can return the error object at its start with no world to
  thread. runs.cpp's externs, written for the older convention, took a
  world argument Lean no longer passes, and `sv_guarded_io` handed that
  garbage to the action as its world; harmless, as the world is never
  read, and now gone.
- **Stops that Lean sees.** A stop is offered first: the next IO
  function compiled in the REPL to start returns `IO.Error.interrupted`,
  which Lean code sees as any other error, so its `try`/`catch`/`finally`
  run, the elaborator's included. The elaborator also has its own
  interruption: `Core.checkInterrupted`, called as it recurses, throws
  once the command's cancel token is set, and each run passes one, set
  along with its flag, so a slow `#reduce` stops cleanly 10 ms after
  Ctrl+C. No command after the one the stop came in is elaborated, and
  the REPL keeps the Lean it had. `do try ticks 1000 finally IO.println
  "cleaned up"` stops 4 ms after Ctrl+C, with the ticks so far and
  "cleaned up". What Lean can't see: a stop that finds pure code (`try
  IO.println (quiet …) finally …`) has no IO result to become, so it's
  cut off once the offer's 50 ms are out, past the `finally`; and code
  that catches the interruption and goes on is cut off 500 ms after it
  took it. `IO.sleep` ends at a stop, so the run goes on to its next
  safepoint: Lean implements it with `dbgSleep`, which runs.cpp wraps
  to sleep in 5 ms slices. Output comes at the end, as before: `#eval`
  gathers it.
- **Masking.** `IO.Ref.modify` is `Ref.take` then `Ref.put`. Take
  empties the ref, and a thread that reads an empty ref shared between
  threads spins until it's filled (`lean_st_ref_take` and `get` loop on
  an atomic exchange). A run cut off between the two leaves the ref
  empty for good, and any thread that reads it spins, at full speed, for
  ever. The desktop had one: `launch` modifies the run's list of apps,
  which the loop reads when the run ends. A mutex held when a run is cut
  off stays locked (`Mutex.atomically` unlocks in a `finally`). So
  runs.cpp wraps those primitives (`--wrap` of `lean_st_ref_take`, `put`,
  and the mutexes' lock, try-lock and unlock) to count what each thread
  holds; a stop that comes meanwhile waits, and the put or unlock that
  ends the region is a safepoint. It reaches interpreted code too: the
  interpreter calls externs through compiled code (their `_boxed`
  versions), which calls the wrapped functions. Compiled code cut off
  midway, ten times each: without masking the ref was left taken 6 to 9
  times and the mutex locked 8 or 9 times (over three runs of the test);
  with it, never, and the stops took no longer (50 ms). A stop is still offered to IO code that holds a
  mutex (the `finally` unlocks it), not to code that holds a taken ref.
  A long critical section holds a stop off until it ends.
- **What needs Lean itself.** All of the above works without changing
  Lean. What would need its compiler or runtime:
  - Compiled loops that neither allocate nor poll (`Busy.spin`): the C
    emitter would have to put polls in loops, as the pass does for the
    REPL.
  - Cheap safepoints in interpreted code: a check the interpreter made
    itself on entering a function (a thread-local load) would cost a
    nanosecond, not 50.
  - Stops as exceptions everywhere, pure code included, so that every
    `finally` runs and what each frame holds is freed: asynchronous
    exceptions, like GHC's `throwTo`, need every frame to unwind the
    Lean way. Today a cut-off is a C++ exception, which skips Lean's
    frames.
  - Masking in Lean (GHC's `mask`) with a per-thread stop flag the
    runtime checks, instead of linker wrappers, which miss calls inside
    the runtime's own library and functions that are inlined.
  - Blocking calls that end at a stop: `IO.wait`, `Condvar.wait`,
    reading a stream. `IO.cancel` only sets a flag for
    `IO.checkCanceled`, and a cancel token only reaches the elaborator.
- **Apps made in the REPL.** `launch` puts an app made by interpreted
  code in a window, and its step and view run in the interpreter on the
  main thread, between frames. A step that never returns would hang the
  desktop: nothing guards the main thread yet.
- **Highlighting by Lean's tokenizer.** Lean's tokenizer
  (`Lean.Parser.tokenFn`) reads one token at a time with the
  environment's token table, so the REPL's own Lean decides what a token
  is, and notation defined in a REPL is read as the parser will read
  it. Each token comes back as syntax with its place in the line: an
  atom (a keyword when it's a word, as Lean's editor decides: `def`,
  `s!`, `#eval`; a symbol otherwise), an identifier, or a literal. A
  line of 52 characters takes 22 µs, about a microsecond a token, and
  one of 200 characters 97 µs; a keystroke, the REPL's step with the
  line read again, 26 µs. Lean's whole parser takes 65 µs on the same
  line, so parsing at every keystroke would be affordable too, but a
  line being typed is seldom a whole term yet, and the parser's error
  would turn the end of every unfinished line red.
- **What the tokenizer leaves to its caller.** It isn't a lexer with an
  API of its own: `tokenFn` is a `ParserFn`, run with an input context,
  a module context (environment, options, namespace, open
  declarations) and the token table (`ParserFn.run`), and the blanks
  before the first token are skipped by hand (`whitespace`). Comments
  aren't tokens: `whitespace` skips them after each token, so a comment
  is whatever lies between tokens and isn't blank. Doc comments (`/--`,
  `/-!`) are tokens whose bodies the tokenizer doesn't read
  (`finishCommentBlock` does). It stops at the first error, with no
  recovery, so the REPL colours the rest of the line red. Its
  positions are bytes of UTF-8 (`String.Pos.Raw`) and the REPL's grid
  counts characters, so each one is counted again (for nothing when the
  line is ASCII).
- **Names that resolve.** `ResolveName.resolveGlobalName` is a pure
  function of an environment, options, the current namespace and the
  open declarations, so an identifier it resolves is drawn as a
  constant: the REPL's own definitions, names reached through `open`,
  and a constant followed by fields. Lean's editor tells more
  apart, variables, functions, types, from the info trees the
  elaborator fills (`Lean.Server.FileWorker.SemanticHighlighting`).
  That takes a line that elaborates, with info trees on (the REPL keeps
  them off), in the language server's request monad: possible after
  Enter, not at each keystroke.
- **Completion.** Lean's own completion (`Lean.Server.Completion`)
  isn't a function of an environment and a name: it works from the info
  trees of an elaborated file at an LSP position, in the server's
  `RequestM`, and answers LSP `CompletionItem`s. What it's made of can
  be used as it is: `Meta.allowCompletion` (no auxiliary recursors,
  matchers, `noConfusion` or internal names), `isProtected`,
  `isPrivateName`, and its rule that a namespace that is also a
  constant isn't offered as a namespace (`Picture.brecOn`, which holds
  its equation lemmas, would be). The REPL's completion is about 60
  lines over those: names by namespace, from every namespace a name
  could be resolved from (the current one and those around it, the
  root, the open ones), what the REPL defined, and keywords from the
  token table (`Trie.findPrefix`). The constants imported are indexed
  by namespace once, as the language server caches its "eligible
  header declarations" in a global: 38,575 names in 2,944 namespaces,
  of 67,237 constants, in 90 ms, in a task of its own after the import,
  so the REPLs' Lean is still ready 140 ms after the desktop starts.
  Tab then takes 2 µs for `Busy.al` (one name), 130 µs for `List.ma`
  (236), 0.9 ms for `Nat.` (2,020): quick enough for the REPL's step, on
  the main thread, as a pure function. Most names are theorems' (219 of
  the 236 for `List.ma`), so they come after the definitions.
  What needs elaboration isn't done: a field after a term (`xs.ma`, which
  the type of `xs` decides) and a constructor by the type expected
  (`.cir`).
- **A value that carries its functions.** A pure module can't call a
  function defined in a module it doesn't import: Lean has no forward
  declarations across modules, short of `@[extern "sym"]` in one and
  `@[export sym]` in the other, joined by the linker by name and checked
  by nothing. The REPL can't import Eval.lean, which imports Lean (the
  REPLs' Lean would then import all of Lean, 1.6 GB), so an `Env`
  carries `tokens` and `complete` as closures that Eval.lean makes with
  it. The REPL's step and view stay pure, as the functions are, and the
  type checker sees every call.
- **A REPL asks for its Lean.** Before its first line a REPL has no
  `Env`, only "the desktop's own", which the loop imports in the
  background. It asks for it as it opens, as the run of an empty line,
  and colours nothing until it comes (140 ms after the desktop starts;
  a millisecond later). An undo can bring back a REPL whose answer went
  to a world that's gone, so a REPL without its Lean asks again each
  second.
- **Colours on the grid.** `Picture` needed nothing new: the grid says
  where every character goes, so a row of several colours is a `mono`
  for each run of one colour, at the column it starts in. A REPL window
  full of highlighted lines draws 156 monos instead of 24, in 375 µs
  instead of 200 (about 1.3 µs a mono: Cairo selects the font, turns
  text into glyphs and composites, per call), and makes its view in 80
  µs instead of 37. A frame still takes about 1.6 ms. A `mono` with a
  colour for each character, one call into the shim a row, would save
  most of that if many windows showed code.
- **Reading an environment from two threads.** The view calls the
  tokenizer on the main thread while a run may be elaborating from the
  same environment on another thread. Nothing needs a lock: the
  environment is persistent data, and the run's closure marked it
  multi-threaded when the run took it, so its reference counts change
  atomically.
- **Comments and strings across lines.** Lean's tokenizer reads a
  whole file as gladly as a line (`whitespace` skips comments across
  line ends), but it can't start inside a comment or a string, and it
  stops at its first error with no recovery, so a file read in one go
  would turn red from its first stray character to its end. The editor
  reads a line at a time, and carries from each line to the next where
  it ended: in code, in a comment so many deep (they nest), or in a
  string. What the line before left open is read to its end by hand,
  and where the tokenizer gives up on a comment or string that doesn't
  end on this line, the line ends inside it: about 40 lines of scanning
  over characters. Raw strings (`r#"…"#`) that span lines aren't
  carried.
- **What a line of a file costs.** About 24 µs a line: all 258 lines of
  Repl.lean in 6.1 ms, as a file opens or the desktop's Lean arrives. A
  keystroke, the editor's step with its line read again, 77 µs; Down,
  1.3 µs. An edit reads the lines below only while they start
  differently than before, so `/-` typed at the top costs 0.26 ms (a
  line inside a comment is only scanned for `-/`), and deleting its `/`
  6 ms, every line read again by the tokenizer. That's on the main
  thread, in the step: a file of 2,000 lines would take some 50 ms, a
  dropped frame or three. Reading only the lines in view, and the rest
  when they come into view, would bound it.
- **A file as lists around the cursor.** As with the REPL's line, the
  file is the lines above the cursor's (nearest first), the cursor's
  line, and the lines below: an edit changes the cursor's line, Up and
  Down move one line from one list to the other, and every world undo
  keeps shares all the lines it didn't change. The view needs only the
  lines in view, which `drop` and `take` find from the cursor's side.
  Jumps (a click far off, Ctrl+End) walk a line at a time.
- **Files as requests, answered at once.** Reading, writing and listing
  files don't go on threads of their own, as runs do: a run can be cut
  off at any safepoint, which includes every allocation, and a write cut
  off midway would leave half a file. Files this size take well under a
  millisecond, so the loop answers on its own thread, as it answers a
  stop with nothing to stop. Lean's `IO.FS.writeFile` truncates and
  writes, so a crash midway would also leave half a file; the loop
  writes beside the file and renames it over (`IO.FS.rename`).
  `System.FilePath.walkDir` lists a tree, with a function that says
  which folders to go into. The desktop's folder is noted as Eval.lean
  compiles, as the sysroot is: in a term elaborator, `getFileName` is
  the module's full path, because Lake passes Lean full paths.
- **An app doesn't know its size.** A view gets the window's size, but
  a step doesn't, and the editor's step must keep the cursor in view as
  it moves, so which line is at the top is state, and the step needs
  to know how many lines fit. Windows don't change size yet, so the
  editor uses the size it asks for. Once they do, apps will need to hear
  their size as an event, as they hear the time.
- **A title from the state.** `App.title` was a constant; an app made
  with `App.asking` can now take it from its state (`titleOf`), so an
  editor's window says which file it has, and whether it's saved.
- **The wheel.** SDL3 gives the wheel in fractions of a step
  (touchpads, fine wheels), with the pointer's place in the same event
  and a flag for "natural" scrolling. The shim sends the fraction; the
  editor adds fractions up until they make a line.
- **A pattern variable can be a constructor.** In `match o with | .read
  text => …`, written inside `namespace Event`, `text` was taken for the
  constructor `Event.text`, and Lean said "Not enough arguments to
  `text`": a name in a pattern is a variable only if no constructor of
  that name is in scope. Apps have many constructors in scope
  (`Picture.text`, `AppEvent.text`, `Event.text`), so pattern
  variables want names that aren't theirs.

## Ideas for next

- Runs the world declares instead of requests: the world would keep
  the runs it waits for, and the loop would start and stop threads to
  match the world now, so undo would stop or restart work along with
  the rest. Pure work can be run again safely; evaluation that changes
  the environment can't.
- Guard the steps and views of apps made in the REPL, on the main
  thread: they have safepoints now, so a watchdog could raise a flag
  for them after a few frames' time.
- Definitions shared between REPLs, or a REPL opened from another's Lean.
- Errors pointed at with a caret under the line, not a column number.
- Completion that needs elaboration: a field or function after a term
  (`xs.ma`) or a constructor by the type expected (`.cir`). Elaborate
  the line up to the cursor in a run, with info trees on, and ask Lean's
  own completion; Tab would answer when the run ends.
- Colours by meaning once a line is entered: it's elaborated then, so
  with info trees on, variables, functions and types could be told
  apart as Lean's editor does.
- Tab again to go through what's offered, or a click on an offered name.
- The REPL: scroll back through the transcript (PageUp, the wheel),
  place the cursor with a click, Ctrl+A and Ctrl+E, and keep the cursor
  in view when a line is taller than the window.
- Undo goes back a press at a time, so it also undoes everything typed
  since the last press. An app could say which of its events make a step
  worth returning to (Enter in a REPL, say).
- Right-click for apps too, perhaps a window menu, now that the right
  button always opens the desktop's menu.
- Resizing windows: an app's `view` already takes its size; its step
  would need to hear it (the editor uses the size it asks for).
- Reload an app from its file (step 7b): Ctrl+R in the editor, with
  the REPLs' Lean no longer importing the apps, so that a file's
  declarations don't clash with themselves.
- The editor: read only the lines in view, and the rest later; select,
  copy and paste; search; undo a keystroke at a time; open a file from
  the REPL; warn before Esc quits with changes not saved.
- Measure proportional text in the view, for layout that wraps (Notes).
  Monospace text can be measured already.
- Display scaling and a resizable window.
