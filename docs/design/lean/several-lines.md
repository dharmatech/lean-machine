# The REPL's line holds several

A REPL's line is one `Line`, the characters before the cursor and
those after it, and "\n" is just another character in it. A paste
brings its lines joined by "\n", and Shift+Enter puts one in, as far
in as the cursor's line, and two more after `:=`, `do` and the like
(`indentAfter`, the editor's rule for Enter). Nothing else in the REPL
had to learn a second kind of line:

- Enter sends the whole text, as it always did. `runCommands` parses
  and elaborates one command after another until the source ends, so a
  block of commands needs nothing new; a term over several lines still
  parses as a term, and goes to `#eval`.
- `lexLine` reads a newline as whitespace, so the block's tokens come
  from one call, a comment that ends at a line's end included. There's
  no `Carry` to pass along, as the editor's lines need: the REPL's Lean
  reads the whole block at once.
- The history and the transcript keep the block as one string, so Up
  brings it back whole, and the transcript shows it as it was entered.
- Tab, and whether the cursor is in a string or a comment, look only
  at the characters near the cursor.

What did change is where the cursor goes. Left and Right cross the
"\n" like any character; Home and End stop at it (`lineStart`,
`lineEnd`). Up and Down move to the line above or below, at the same
column or that line's end (`Line.up`, `Line.down`), and only from the
first or last line do they go through the history. In the view, each
line starts its own rows (`lineSpans`), the first after the prompt and
the rest after as many spaces, so the indents line up as they were
written, and `promptCursor` counts the rows above the cursor's line. A
block taller than the window shows from the cursor's row down.

Lean gives a message's line and column in the source. For one line,
the REPL says only the column; for several, `saidOf` says both (`line 2,
col 2`), the column counted after the `#eval ` it put in front of a
term only on the first line.

[↑ Lean inside the desktop](README.md)
