# An app hears a drag

An app hears the left button go down (`AppEvent.press`), the pointer
move (`motion`) and the button come up (`release`), in its body's
coordinates. A press in a window's body raises and focuses the window
first, then goes to its app, so the first press on a window that wasn't
focused already does something.

Motion and release go to the focused window's app, wherever the
pointer is: past the window's edges, over another window, over the
taskbar. So a drag that leaves the window goes on, and a slider's knob
stops at the end of its track while the pointer goes further. While
the world drags a window itself, by its title or an edge, its app hears
none of it.

The world doesn't say whether the button is down: motion comes either
way. An app that drags something remembers that it holds it, from its
press to its release; a slider keeps `held`. If the focus moves during
a drag (Ctrl+Shift+H minimizes the window), the release goes to another
window, so a slider also lets go at a press outside it.

A press starts a step undo can return to, and motion and release
don't. So one undo takes back a whole drag, however many motions it
had, and the window's focus with it.

[A slider, made in the REPL](../../explore/slider.md) has one to try.

[↑ The world and apps](README.md)
