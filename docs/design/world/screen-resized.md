# A smaller screen pushes windows in

When the host's window changes size, the world hears it as
`Event.screen w h`, and `World.onScreen` puts every window on the new
screen. A screen that grows moves nothing: a window stays where it was
put. A screen that shrinks pushes windows in from its right edge and
from the bar, the way a wall would, but only as far as it has to.
`Rect.keepOn` keeps as much of a window on the screen as there was
before. A window that hung 140 pixels off the right edge still hangs
140 off, and the title stays where a press can find it. A window
bigger than the screen stops at the left and top edges and hangs off
the others, still its own size: only the user resizes a window.

A maximized window is different: it fills the new desktop, and its app
hears its new size. The place it goes back to is pushed in like any
window, so restoring it on a small screen doesn't put it out of reach.
An open menu is kept on the screen, as it was when it opened. The
taskbar needed nothing: it's laid out from the screen every time it's
asked for. With a narrower bar, the hint gives way to the buttons
sooner.

## Undo keeps the screen

The screen's size isn't a step to undo: it's the size of the host's
window, and undo can't change that. So `.screen` makes no undo step
(`World.commits`), and the worlds kept for undo keep the screen they
had. `Desktop.undo` puts the world it returns to on the screen there
is now, with `World.onScreen`, pushed in the same way. An undo after
the screen shrank brings back the windows as they were, inside the
smaller screen. Since `onScreen` does nothing when the size is the
same, undo on an unchanged screen is what it always was.

How the screen came into the world: [The screen is in the
world](screen.md)

[↑ The world and apps](README.md)
