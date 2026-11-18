# A maximized window remembers where it was

A maximized window keeps the `Rect` it came from (`Win.restore`), and
while that is `some`, the window is maximized. `World.toggleMax`
swaps the two: maximizing keeps the window's place and puts it at
`desktopRect`, the screen above the bar; restoring puts it back. Both
go through `World.place`, so the app hears its new size
([An app hears its size](app-size.md)). A reload into a maximized
window keeps it maximized, with the same place to go back to.

A maximized window that's dragged stops being maximized. Dragged by its
title, it takes its old size under the pointer, as far along the title
as the pointer was. Dragged by an edge, it keeps its size and resizes
from there. Neither happens until the pointer has gone 4 pixels
(`dragSlop`). Otherwise the first click of a double click on a
maximized title would restore the window with the smallest jitter, and
the second click would maximize it again.

The double click comes from SDL, which counts clicks in a row itself,
so the world keeps no timers. The shim passes the count along with the
button (`Event.press x y clicks`). Even counts toggle, so a triple click
is a double click and one more.

Ctrl+Shift+M is the first desktop key that makes an undo step: until
now only presses and reloads did (`World.commits`). So `Desktop.step`
asks the world about keys too, and Ctrl+Shift+Z stays its own case.

Adding the count to `Event.press` turned up a trap in Lean's patterns:
[A default argument is a value in a pattern](default-in-a-pattern.md).

[↑ The world and apps](README.md)
