# A long, fast resize stalls on Wayland

A known issue, not yet understood. On GNOME's Wayland session, dragging
a corner of the Lean Machine window fast and for a long time makes it
stop following the pointer, then catch up all at once, after as much as
two seconds. A slow drag keeps up, and maximizing and full screen
aren't affected.

Seen on Ubuntu with GNOME Shell 50.1, SDL 3.4.2, libdecor 0.2.5 (whose
GTK plugin draws the window's title and edges on GNOME) and NVIDIA's
open kernel module 595.99, where SDL draws with its `opengl` renderer.

## What was measured

A library preloaded into the desktop timed every frame: the wait for
events, Lean's step and Cairo's drawing, the canvas's upload, and the
present. During a drag, a frame took 2 to 4 ms of Lean and drawing and
about 1.5 ms to present, and each took one resize. Resizes came about
every 33 ms while the window kept up. Each stall was a single call to
`SDL_WaitEventTimeout`, which the loop asks to wait at most 100 ms: it
lasted 0.4 s early in a drag, and 1.5 to 2 s after twenty seconds of
dragging.

The same drag with `SDL_VIDEO_DRIVER=x11`, through XWayland, where
GNOME draws the window's frame itself, never stalled: the longest wait
was the loop's own 100 ms.

## What it isn't

- Lean Machine's own work. 3000 resizes under SDL's `offscreen`
  driver, with no window manager, took 4 to 14 ms a frame from the
  first to the last, and memory stayed flat.
- A leak. Resized as fast as it would go on the real desktop for 20
  seconds, the process's memory, its shared-memory buffers and its open
  files stayed flat.
- A texture made again at every size. On the same GPU that costs half a
  millisecond a frame more than keeping one, and no more as it goes on.

## What's still odd

A watchdog thread that took the main thread's stack after 300 ms in the
wait worked on the real desktop in a short test, but didn't fire once
during the stalls. That suggests the whole process stops, not only its
wait for events. The machine had 7 of its 8 GB of swap in use at the
time, which may or may not matter.

## Where to look next

- A stack taken from outside the process during a stall (`gdb -p`,
  `perf record -g`), since a thread inside it doesn't seem to run.
- Another compositor, KDE's say, which draws the window's frame itself,
  to tell libdecor's part from the rest.
- A newer SDL or libdecor, and Mesa's drivers in place of NVIDIA's.

Until then: maximize the window or press F11, or resize more slowly.
`SDL_VIDEO_DRIVER=x11` avoids it, through XWayland; Lean Machine leaves
SDL's own choice, Wayland, alone.

[↑ Drawing and input](README.md)
