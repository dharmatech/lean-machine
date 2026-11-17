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

Drag a window by its title, click one to raise it, click the box on a
title to close it, press N for a new window at the pointer, U to undo, Esc
to quit. The bar at the bottom counts the earlier worlds that undo can
return to.

```sh
.lake/build/bin/desktop --test        # the pure world, driven by a script of events
.lake/build/bin/desktop --frames 20   # stops after 20 frames
SDL_VIDEO_DRIVER=dummy .lake/build/bin/desktop --frames 20   # the same, with no display
```

`--test` writes `after-script.png` and `after-undo.png` in the current
directory.

Needs Lean 4.36 through elan (`lean-toolchain` pins it), Cairo, and SDL3's
shared library. SDL3's headers (`libsdl3-dev`) are not needed.

## How it's built

The Lean code is one module per file in `LeanMachine/`, in the
`LeanMachine` namespace, with a thin `Main.lean` on top. `Picture`,
`World`, `Desktop` and `View` are pure and import only each other. Only
`Host` calls C, and only `Host` and `Main.lean` touch `IO`.

- `Picture.lean`: `Picture`, plain data (rectangles, text, groups).
- `World.lean`: windows, the pointer and events.
  `World.step : World → Event → World` drags, raises, focuses, closes
  and opens windows.
- `Desktop.lean`: `Desktop` is the world now and every world before it;
  undo takes the previous one. Also `start`, the desktop the program
  starts with.
- `View.lean`: `Desktop.view` returns a `Picture`.
- `Host.lean`: the calls into `shim.c` (a canvas and one window),
  `Event.decode` for the events the shim hands back, and `render`, the
  only code that draws.
- `Main.lean`: `run`, the loop and the only code that does I/O; `test`
  for `--test`; and `main`.
- `shim.c` is the only C: Cairo draws into an image in memory, and SDL3
  shows it in one window and hands back events. No GPU in the design.
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
- **SDL3 without headers.** `shim.c` declares the ten SDL calls it uses
  and reads event fields at the offsets Schevana v0 reads.
- **Bindings.** There are no Lean bindings for Cairo. There are some for
  SDL3 ([ValorZard](https://reservoir.lean-lang.org/@ValorZard/SDL3)) and
  raylib ([Raylib.lean](https://github.com/KislyjKisel/Raylib.lean)), but a
  `Picture` needs only a few coarse C calls, so owning them is cheap.

## Ideas for next

- Apps as a protocol: an `App` whose `step` and `view` return new apps,
  so the desktop holds an open list of them.
- Measure text through Cairo, for layout.
- Display scaling and a resizable window.
