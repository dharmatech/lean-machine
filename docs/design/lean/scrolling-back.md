# The REPL scrolls back to an entry and a row

Until the wheel turns, the REPL's view follows the newest rows: it cuts
only the newest entries into rows, as many as fill the window, and the
line being edited stays at the bottom. Scrolled back, the view holds on
to its top row instead (`Repl.top`): an entry, counted from the oldest,
as a place in a selection is ([Copying from the REPL](copying-from-the-repl.md)),
and which of that entry's rows. The view starts there and goes on as
far as it fits (`Repl.layout`), so the line and the cursor may be
below it, and not drawn.

Why not count rows instead:

- Rows back from the bottom would slide: what a run brings when it ends
  goes in at the bottom, and pushes everything above it up. Held by an
  entry, the view stays on what you're reading while a run ends.
- Rows down from the top would mean cutting every entry into rows to
  know where the view is. An entry and a row cut only the entries from
  there down to the bottom of the view.

A wider or narrower window cuts an entry into other rows; a row the
entry no longer has is its last.

The wheel moves the top three rows a step, a touchpad's fractions
adding up as in the editor, and PageUp and PageDown (with Shift too, as
in a terminal) a row less than the view. Moving goes through the
entries' rows (`rowsBack`, `rowsOn`), counted without being cut
(`Entry.rowCount`). From a top where the view would show the newest
rows anyway, it follows them again (`scrolledTo`, against `followTop`),
so scrolling on past the bottom ends up there, and so does scrolling a
REPL that has nothing to scroll.

A drag above or below the rows scrolls a row for each motion, as the
editor's does, so a selection can go on past what's in view. A key that
does something (typing, a paste, Enter, an edit, Tab, Ctrl+C when it
stops a run) brings the view back to the newest rows, as a terminal
does, and Ctrl+C when it copies leaves it where it is. A run that ends
leaves it too.

The view is in the REPL's state, so undo takes it back with the rest;
the wheel doesn't start a step of its own, so it goes back with
whatever step undo returns from.

[↑ Lean inside the desktop](README.md)
