# A drag moves edges

Moving a window and resizing it are one kind of drag. A press records
the window's `Rect` and where the pointer was, and which `Edges` will
move. A press on the title takes all four edges, which moves the
window. A press on an edge takes one, and a corner or the grip takes
two, which resizes it. Once the pointer has gone 4 pixels
(`dragSlop`), so that a click doesn't move a window, each motion puts
the window at `Rect.drag` of the rectangle it started from, so a drag
never builds up rounding.

A window resized by hand stays at least `minW` by `minH` (200 × 140,
enough for the title's close box and three lines of the editor). An
edge being dragged stops at the desktop's edges, the bar included,
unless it was already past them. A move goes anywhere but under the
taskbar: the bar is in front of the windows and takes presses, so a
window stops with the top 20 pixels of its title above it
(`titleKept`), where a press can find it.

The frame is 3 pixels wide, too thin to hit easily, so an edge can be
grabbed from up to 4 pixels outside it (`reach`). Within 16 pixels of
a corner, a grab takes both of the corner's edges. On top, the title's
first 3 pixels are the edge; the rest of it moves the window. The edge
under the pointer lights up, since the shim doesn't change the pointer's
shape.

Every change of a window's place goes through `World.place`, which also
tells the app its new size ([An app hears its size](app-size.md)).
Maximizing does that ([A maximized window remembers where it
was](maximizing.md)), and tiling and cascading will only need to
compute rectangles and place windows at them.

[↑ The world and apps](README.md)
