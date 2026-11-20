# Copying from the REPL

What the REPL shows is parts, in order: each entry of the transcript,
oldest first, then the line being edited. A selection is two places
between characters (`Spot`), each a part and how many characters into
it. An entry is named by its place counted from the oldest, so a place
stays put as entries come in below it, and the line comes after them
all. A press puts both ends where it lands, a drag moves the second to
the pointer, and what's selected runs between them, whichever comes
first (`Repl.selection`).

To find what a press is on, the step needs the view's rows, so the
REPL keeps the body's size from the last `resize`, as the editor does,
and the view and the step share one layout (`Repl.layout`). Each row
knows what it shows of its part (`Span`): from which character to
which, after how many columns of prompt, and whether one of the part's
lines ends there. A press goes to the nearest place between two
characters in its row (`pointAt`); on the row that says a run is
going, to the end of the newest entry; on what Tab offered, to the end
of the line; above the rows, to the start of the first, and below
them, to the end of the last.

What's copied reads as it was written, not as it was cut into rows: a
line that wraps is one line (`Repl.selected`). As for the prompts:

- Within one part, its characters and nothing else. Part of a line
  entered, or a whole block, pastes back into the REPL as it was.
- Past one part, each part on lines of its own, and each line entered
  whose start is selected led by its `> ` (a line after the first in a
  block by two spaces, as the view indents it), so it reads the way
  the REPL showed it: `> sq 12`, then `144`. The highlight takes in
  the prompts that come along.

Ctrl+C asks the loop to copy, as the editor does (`Request.copy`:
[Copy and cut are requests](../editor/copy-and-cut.md)), and with
nothing selected it stops a run or clears the line, as it did. Unlike
the editor, the REPL ends its selection when it copies, so a second
Ctrl+C stops the run: copying some output while a line runs never
keeps Ctrl+C from stopping it. Ctrl+Shift+C only copies. A key that
does something (typing, a paste, Enter, an edit, Tab) ends the
selection too, and a press elsewhere starts another. A run that ends
leaves it alone, as the entries it brings come after it.

A press starts a step undo can return to, so undo after a drag takes
the selection back with the press. A drag above or below the rows
scrolls the view, so a selection can go past what was in view
([The REPL scrolls back to an entry and a row](scrolling-back.md)).

[↑ Lean inside the desktop](README.md)
