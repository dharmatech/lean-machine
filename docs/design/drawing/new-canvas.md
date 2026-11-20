# A resized window draws on a new canvas

SDL opens the window resizable (`SDL_WINDOW_RESIZABLE`), so the window
manager gives it edges to drag and a maximize button. It can't be made
smaller than `Screen.least`, 640 × 400 (`SDL_SetWindowMinimumSize`);
the world would take any size, but a smaller desktop has no room to
work in. When the window's size changes, SDL sends
`SDL_EVENT_WINDOW_RESIZED` (`0x206`) with the new width and height at
20 and 24, the window's size in the same units as the pointer's place.
The shim hands it back as kind 9, which `Event.decode` makes
`Event.screen`, and the world fits itself to it ([A smaller screen
pushes windows in](../world/screen-resized.md)).

The canvas is a Cairo image of a fixed size, so the loop makes a new
one when the world's screen has changed, after the events of a pass,
however many resizes they held. Lean frees the old one when nothing
holds it. The shim's texture, which each frame is copied into, follows
the canvas: `sv_host_present` makes it again when the canvas is a new
size. So the loop's only job is to keep the canvas the size of the
world's screen, and nothing in C keeps the size apart from it.

A resize was tried without a window manager: a library preloaded into
the desktop, under SDL's `offscreen` driver, resized the window
between frames and saved what the renderer showed, at 900 × 600,
1500 × 950, and 300 × 200, which SDL held at 640 × 400. All drew
right with the software renderer (`SDL_RENDER_DRIVER=software`). With
the offscreen driver's GL renderer, the window that grew showed only
its first 1280 × 800: that driver's GL surface keeps its first size,
which no real window has to.

[↑ Drawing and input](README.md)
