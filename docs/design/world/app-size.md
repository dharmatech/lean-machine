# An app hears its size

A view is handed the window's size, but a step isn't. The editor's
step needs to know how many lines fit, to keep the cursor in view and to
find the line a click lands on. Its state is hidden in closures
([Apps are opaque](apps-are-opaque.md)), so the desktop can't set a
size in it. The desktop tells the app instead, with an event,
`AppEvent.resize w h`, the way it tells the time. An app hears it as its
window opens, before its first tick, and again whenever the body's size
changes. An app that needs its size keeps it in its state, as the
editor does; Notes and Inspector show it beside the size their view is
given, as a check.

So the size lives in two places: the window's rectangle and the app's
state. One function keeps them in step: every change of place goes
through `World.place`, which tells the app when the body's size
changed (a move alone tells it nothing). `World.fresh` tells a new
window's app.

Once the size was the user's to choose, every count the editor made from
it had to be read again for small windows. Rows and columns are `Nat`s,
where `1 - 2` is `0` and not an error, and `Float.toUInt64` turns a
negative number into `0`. So nothing fails: a count that goes wrong
only gives a wrong view. The editor keeps at least one row and one
column, and avoids `rows - k` in its tests.

Undo took no work. The app's size is in its state, and its state is in
the world, so one undo puts back the window's old size and the editor's
old size, first line in view and all, together.

How the drag works: [A drag moves edges](resizing.md)

[↑ The world and apps](README.md)
