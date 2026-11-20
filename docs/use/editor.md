# The editor

The Editor edits the desktop's own Lean files. It opens on a list of
them: type part of a path to narrow it (`apps/cl`), Up and Down to
choose, Enter or a click to open one.

In a file, the arrows, Home, End,
PageUp, PageDown, Ctrl+Home and Ctrl+End move the cursor, a click puts
it where it lands, and the wheel scrolls; Backspace and Delete join
lines at their ends, and Enter starts the new line as far in as the
last, two more after `:=`, `do`, `where`, `=>`, `by`, `then` or
`else`.

Ctrl+V pastes text you copied elsewhere at the cursor, lines and all,
with each tab as two spaces. In the list of files, it pastes into
what's typed to narrow it.

To select, hold Shift while you move the cursor, drag over the text,
or press Ctrl+A for the whole file. Drag past the top or bottom and the
file scrolls as you move the pointer. The status line says how much is
selected. Typing, Enter or Ctrl+V replace what's selected, Backspace
and Delete take it out, and a move without Shift ends the selection.

Ctrl+C copies what's selected, and Ctrl+X cuts it, for a paste here or
in any other program. With nothing selected, Ctrl+C stops a reload
instead; Ctrl+Shift+C only ever copies.

The file is coloured
as the REPL colours a line, with comments and strings that span lines
(`/- … -/`, the module's doc comment) coloured as one. Tab completes the
name before the cursor from the desktop's Lean (`TimeOfDay.` offers its
fields), or indents.

Resize its window and it shows more or fewer lines and columns, with
the cursor still in view.

Ctrl+S saves (the title's `•` says there are
changes not saved), Ctrl+O goes back to the list (twice, if there are
changes not saved). Esc still quits the desktop, changes and all.

More: [Reloading an app](reloading.md)

How it works: [The editor](../design/editor/README.md)

[↑ Use](README.md)
