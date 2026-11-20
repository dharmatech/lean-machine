# The screen is in the world

The screen was two constants, `screenW` and `screenH`, 1280 by 800,
and a dozen places read them: a drag stops at the desktop's edge, a
maximized window fills the screen above the bar, the taskbar spreads
its buttons across it, a new window and the menu are kept on it, and
the view paints it. For the host's window to be resized, the size has
to be able to change, so it's a value now, held by the world:
`World.screen`, a `Screen` with a width and a height, 1280 by 800 to
start with.

It's in the world, not the desktop, because `World.step` is what reads
it: a drag, a maximize, a press on the bar. The constants made from it
became functions of it: `Screen.barY`, the top of the bar;
`Screen.inBar`; and `Screen.desktop`, where a maximized window goes,
which was `desktopRect`. `Rect.drag` and `Taskbar.of` are handed the
screen, and the taskbar keeps its top (`Taskbar.y`), so that the view
draws its buttons where a press finds them. Main.lean makes the canvas
and opens the window at the size of the start's screen.

When this landed, nothing changed the screen yet. Every image `--test`
wrote came out the same as before, apart from the times some of them
show. What changes it now: [A smaller screen pushes windows
in](screen-resized.md)

[↑ The world and apps](README.md)
