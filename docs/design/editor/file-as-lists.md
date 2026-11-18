# A file as lists around the cursor

As with the REPL's line, the
file is the lines above the cursor's (nearest first), the cursor's
line, and the lines below: an edit changes the cursor's line, Up and
Down move one line from one list to the other, and every world undo
keeps shares all the lines it didn't change. The view needs only the
lines in view, which `drop` and `take` find from the cursor's side.
Jumps (a click far off, Ctrl+End) walk a line at a time.

[↑ The editor](README.md)
