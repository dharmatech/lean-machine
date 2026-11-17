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
to quit. Clock is a clock. The REPL echoes each line you enter, for now:
click in it and type; Left, Right, Home, End, Backspace and Delete edit
the line, and Up and Down go back and forth through earlier lines.
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
kind of picture. It also prints the REPL's line and history after that
script, and what `Event.decode` makes of a few events as
the shim hands them back, and the monospace font's own advance beside
`monoAdvance`'s.

Needs Lean 4.36 through elan (`lean-toolchain` pins it), Cairo, and SDL3's
shared library. SDL3's headers (`libsdl3-dev`) are not needed.

## How it's built

The Lean code is one module per file in `LeanMachine/`, in the
`LeanMachine` namespace, with a thin `Main.lean` on top. `Picture`, `Key`,
`App`, the apps in `Apps/`, `World`, `Desktop` and `View` are pure and
import only each other. Only `Host` calls C, and only `Host` and
`Main.lean` touch `IO`.

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
  size, a `step` that returns the app an event makes (`none`: no
  change), and the `size` a new window gives it. `App.of` makes one from
  a state of any type, a step and a view, and hides the state's type, so
  the desktop holds apps of every kind in one list. `AppEvent` is an
  event in the app's own coordinates, a key with its modifiers, typed
  text, or a tick with the `TimeOfDay`.
- `Apps/Clock.lean`: an analog face with the time in digits under it,
  after Schevana's `apps/clock.ss`. `clockFace` is a pure function of the
  time and the size; the app keeps the last tick's time and changes only
  when the second does.
- `Apps/Repl.lean`: a line editor over a transcript; for now Enter
  echoes the line. The line is a pair of lists, the characters before
  the cursor (nearest first) and those after it, so every edit is a cons
  or an uncons. Up and Down walk the history and come back to the line
  being typed. The transcript is a list, newest first, and the view
  cuts only the newest entries into rows, as many as fill the window;
  long lines wrap at the window's width in columns. Rows start at the
  top, and once they overflow the oldest go off the top, so the newest
  and the line being edited stay in view.
- `Apps/Placeholder.lean`: stands in for apps not written yet. A click
  drops a dot where it lands; it shows what was typed into it and the
  last key it heard.
- `World.lean`: windows, the pointer, the menu and events. Each window
  holds an app. `World.step : World → Event → World` drags, raises,
  focuses and closes windows, passes ticks to every app, and passes other
  events, keys and text included, to the focused window's app, moved
  into the app's coordinates. Ctrl+Shift+N opens the menu at the pointer.
  The world holds a `catalog` of apps, the menu's items, but knows none
  of them by name. `World.launch` opens an app in a new window, kept on
  the screen and told the time first. `World.commits` says which events
  start a step undo can return to: a press that does something.
- `Desktop.lean`: `Desktop` is the world now and every world before it;
  undo (Ctrl+Shift+Z) takes the previous one, apps' states included.
  The start desktop opens the REPL, Clock, Inspector and Notes. Also `catalog`,
  what the menu opens, and `start`, the desktop the program starts with,
  opened with `launch` as the menu would.
- `View.lean`: `Desktop.view` returns a `Picture`. Each app's view is
  moved to its window's body and cut to it. The menu draws over
  everything, its item under the pointer lit.
- `Host.lean`: the calls into `shim.c` (a canvas and one window),
  `Event.decode` for the events the shim hands back as a `RawEvent` (the
  right button is `Event.menu`; SDL's keycodes and modifier bits become a
  `Key` and `Mods`), `localTime` (through
  Lean's `Std.Time`), and `render`, the only code that draws.
- `Main.lean`: `run`, the loop and the only code that does I/O. Each
  pass waits for events, but not past 100 ms or the next second, applies
  them, ticks with the time, and draws. Also `test` for `--test`, and
  `main`.
- `shim.c` is the only C: Cairo draws into an image in memory, and SDL3
  shows it in one window and hands back events, text input included.
  No GPU in the design.
- `lakefile.lean` builds the `LeanMachine` library and `Main.lean`,
  compiles `shim.c`, and links them into `desktop`.

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
  already. `step` returns `Option App`, and `none` ends the chain. An app
  that keeps state refers to itself, so it can't be total; `App.of` is
  the one `partial` definition, and apps passed to it stay total.
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

## Ideas for next

- The REPL: scroll back through the transcript (PageUp, the wheel),
  place the cursor with a click, Ctrl+A and Ctrl+E, and keep the cursor
  in view when a line is taller than the window.
- Undo goes back a press at a time, so it also undoes everything typed
  since the last press. An app could say which of its events make a step
  worth returning to (Enter in a REPL, say).
- Right-click for apps too, perhaps a window menu, now that the right
  button always opens the desktop's menu.
- Resizing windows: an app's `view` already takes its size.
- Measure proportional text in the view, for layout that wraps (Notes).
  Monospace text can be measured already.
- Display scaling and a resizable window.
