# Reloading an app

Ctrl+R reloads the apps the file defines (its constants of type
`App`), from the file as it is in the editor, saved or not: the
desktop's Lean elaborates it on a thread of its own (Clock.lean in
about 0.1 s, Editor.lean in 1.1 s; Ctrl+C stops it), and if Lean finds
no error, each app takes the old one's place in the menu and in every
window opened from it, where the window is, starting afresh. When no
window has it, it opens beside the editor. Ctrl+Shift+Z brings the old
apps back. The editor that reloads its own file keeps it: the new
editor opens beside it.

Lines Lean said something about get their
numbers in red (an error), amber (a warning) or blue, and with the
cursor on one, what Lean said shows in a box above the status line;
editing the line takes its mark away. After a reload the file's own
names are coloured and completed.

Only files that import nothing but
Init and the desktop's modules other than the apps can be reloaded
(not Desktop.lean, View.lean or Main.lean). Boids.lean can, since its
simulation is built into the desktop's Lean: a reloaded Boids flies as
fast as the menu's. The simulation's own files, in Apps/Boids/, can't
be reloaded, nor can the other modules the desktop's Lean has built in
(Text.lean, World.lean, …). Ctrl+R on one of them says so; rebuild the
desktop to change them.

How it works: [Reloading](../design/reloading/README.md)

[↑ The editor](editor.md)
