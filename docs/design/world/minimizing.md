# A minimized window is still in the world

A minimized window stays in the world's list of windows, where it was
in front of or behind the others, with a flag (`Win.minimized`). Its
place and `restore` don't change, so no `World.place` is needed either
way, and it comes back as it was, maximized if it was
([A maximized window remembers where it was](maximizing.md)). Undo
covers it like everything else in the world: a press on its box or its
button, or Ctrl+Shift+H, is one step (`World.commits`).

`World.visible` gives the windows that aren't minimized. Only those are
drawn and found by a press (`World.grabAt`) or the wheel
(`World.hit`), so a minimized window can't be pressed or focused, and
hears no keys. Minimizing the focused window gives the focus to the
frontmost window left (`World.frontmost`). Bringing one back
(`World.focusOn`) raises and focuses it, which is also what a click on
another window's button does. Tiling and cascading will place the
visible windows, and leave the others on the taskbar.

Its app still hears ticks and how its runs ended. A REPL or an editor
asks for its Lean on a tick, a clock should be right the moment it's
back, and a run going on in a minimized REPL should still finish. Only
drawing and input stop. Schevana pauses a minimized window's frames,
but not its timers; here a tick is both, so it goes on.

The taskbar is in front of every window: a press in it goes to a
button or nowhere, never to a window that's partly under it, and a
maximized window's bottom edge, which could be grabbed from 4 pixels
below it, can't be grabbed from inside the bar. The world lays the bar
out (`World.taskbar`), as Schevana's bar does, so that a button is
drawn where a press finds it. That needs the width of text, which the
world can only guess
([The taskbar guesses how wide text is](../drawing/guessing-text-widths.md)).

[↑ The world and apps](README.md)
