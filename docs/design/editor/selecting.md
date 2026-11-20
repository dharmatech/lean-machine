# Selecting is a mark and the cursor

The selection is the cursor and one more place, the mark: a line and
a column where the selection started (`Editor.mark`). It runs from the
mark to the cursor, whichever comes first (`Editor.selection`); when
they're the same place, nothing is selected. The file itself doesn't
change, so selecting is cheap: a move with Shift is a move.

- Shift with a move (the arrows, Home, End, PageUp, PageDown,
  Ctrl+Home, Ctrl+End) puts the mark where the cursor was, unless
  there is one, and then moves. A move without Shift drops the mark.
- A press in the file puts the mark where it lands, and starts a drag:
  each motion until the release moves the cursor to the pointer
  (`pointAt`). Above or below the lines in view, the pointer is on the
  line just past them, and `follow` scrolls one line to show it, so a
  drag held still out there stops; it scrolls a line for each motion.
- Ctrl+A puts the mark at the start of the file and the cursor at its
  end.
- Every edit drops the mark. What's typed, entered or pasted first takes
  the selection out (`Editor.replacing`); Backspace and Delete only take
  it out (`Editor.removing`). Either way it's one edit, and the lines
  after it are read again as after any edit.

The file is lists around the cursor's line
([A file as lists around the cursor](file-as-lists.md)), so taking a
selection out goes to its start (`goTo`) and drops what follows, up to
its end, from the cursor's line and the lines below
(`Buffer.remove`): no line above the selection is touched.
`Buffer.between` reads the text selected, for the clipboard next.

The view draws a box behind what's selected of each line in view, and
one column more for a line the selection goes on past, so a selected
line end shows. The status line counts what's selected: characters on
one line, or lines.

A press starts a step undo can return to, so undo after a drag takes
the selection back with the press; selecting by keys, like moving, is
part of the step before it.

[↑ The editor](README.md)
