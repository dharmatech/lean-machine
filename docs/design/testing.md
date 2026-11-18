# What `--test` checks

`--test` puts what it writes in `.lake/test/`, wherever it runs from;
git ignores it, and it can be deleted at any time. It writes
`after-script.png`, `after-undo.png`, `menu.png` (the menu open) and
`repl.png` (the REPL after a script of typing, editing and history),
and `sampler.png`, one of each kind of picture. It also prints the REPL's line, history and first
entries after that script, and what `Event.decode` makes of a few
events as the shim hands them back, and the monospace font's own
advance beside `monoAdvance`'s. It prints the tokens the REPL's Lean
reads in two lines, and what Tab makes of names with one completion
and with several, and writes `repl-highlight.png` (lines of every kind
of token, and a line being edited), `repl-complete.png` (`Picture.`
and Tab) and `repl-complete-many.png` (`List.ma`, 236 names). It
times reading a line's tokens, a keystroke, Lean's parser on the same
line, Tab on a few names, making the index of names, and drawing a
REPL window full of highlighted lines against the same lines in one
colour. Then it evaluates Lean on real threads
through the desktop's REPL and the loop's `feed`, and prints what came
back from each line: definitions, a type error, a namespace across
lines, `world`, printed output. Busy work and loops defined in the REPL
are stopped by Ctrl+C after 300 ms (`repl-running.png` is the REPL with
one going, `repl-runs.png` after them all). It times loops defined in
the REPL with safepoints and without, then stops lines that Lean sees
the stop in, or doesn't: a `try … finally`, pure code inside one, a
loop that catches the stop and goes on, `IO.sleep`, a loop without
safepoints, a slow `#reduce` (`repl-interrupt.png`). An app made in the
REPL is launched and clicked (`repl-launch.png`); an undo takes a
definition back (`repl-undo.png`); two REPLs evaluate at once. It also
prints a frame's time with a run going, what closing the REPL did to
its run, and the RSS after 50 runs were stopped. Last, it cuts off
compiled code ten times in the middle of `Ref.modify`, and ten times
while it holds a mutex, with masking off and then on, and says how
often the ref was left taken or the mutex locked.

Right after the first script and the REPL typed into, before the
highlighting, `--test` resizes windows. From the start desktop it drags Notes by its grip,
moves it by its title, drags Inspector's left edge past the smallest
width, the REPL's top edge (grabbed from just above it) past the top
of the desktop, and Clock's bottom left corner past the bar. After each
drag it prints the window's rectangle, and, for Notes and Inspector, the
size they show beside the size they heard (`resize.png`, the pointer
just right of Notes, its edge lit). Then it undoes once, and again. An
editor alone is told sizes: its rows, columns, first line and column
in view, and where a press lands, down to the smallest window. On the
desktop, an editor on Clock.lean, its cursor on line 31, is made 300
shorter by its bottom edge (`resize-editor.png`), and the cursor's line
is still in view. Undo puts the size back. Last, Clock is made wider by
its left edge and reloaded from the editor, and it keeps that size.

Then maximizing. Notes is maximized by the box on its title and
restored by it; Clock by a double click on its title, which one undo
takes back, and restored by another; the REPL by Ctrl+Shift+M, undone.
Inspector, maximized, is pressed in the middle of its title and nudged
2 pixels, and stays maximized; dragged 100 down, it's back at its old
size under the pointer. Maximized again and dragged by its right edge,
it's a normal window 300 narrower. A reload keeps a maximized clock
maximized, and its box puts it back where it was. An editor on
Clock.lean, maximized, shows 36 lines (`maximize.png`).

Then minimizing and the taskbar. It prints the buttons at the start.
Notes is minimized by its box, and focus goes to Inspector; a press
where Notes was finds nothing (`taskbar.png`, the pointer on Clock's
button). Notes' button brings it back in front and focused; pressed
again, it minimizes Notes, and undo takes that back. Ctrl+Shift+H
minimizes the focused window three times until nothing is focused,
and once more makes no step undo returns to. Inspector's button brings
it back. Clock, maximized, minimized and ticked at 10:09:00, comes back
maximized saying 10:09:00; minimized again and reloaded, it stays
minimized, comes back maximized, and its green box restores it. With
Inspector maximized, the pointer 2 pixels into the bar on Clock's
button lights no edge, and a click there focuses Clock. A click on the
bar over Notes, dragged partly under it, does nothing and makes no
step; dragged 300 further down, Notes stops with the top 20 pixels of
its title above the bar. Last, Clock, Inspector, Notes and Clock are opened from the menu,
one at a time, with each button's width and whether the hint has room:
it gives way at six windows. Two are minimized (`taskbar-many.png`). It says whose
boxes show what they do with the pointer on the REPL's minimize box, on
its title left of the boxes, on its top edge above them and on its right
edge (only the first), and on a maximized Notes' green box (`boxes.png`,
the REPL's behind Notes; `boxes-max.png`, the restore glyph).

Between the REPL's highlighting and its runs, `--test` tries the
editor. It prints the tokens of six lines of a file that leave a
comment, a nested comment, a string and a doc comment open for the next
line. An editor on its own, its requests answered at once, opens a
scratch copy in `.lake/test/editor/`: it prints the file's lines, where
each starts and what it leaves open, after `/- ` is typed at the top and
after ` -/` closes it three lines down, after Enter and Backspace join
and split lines, then saves (Ctrl+S) and prints what's on disk, and
leaves with Ctrl+O, once with changes and then again. On the desktop it
opens the Editor from the menu (`editor-files.png`), opens Clock.lean by
typing `apps/cl`, and Tab after `TimeOfDay.` (`editor-complete.png`),
then opens a comment at the top and turns the wheel
(`editor-comment.png`). A press and the wheel move the cursor and the
view of Editor.lean. Last, it times reading every line of Repl.lean, a
keystroke in the middle of it, opening a comment at its top and closing
it again, Down, and drawing an editor full of code.

Then reloading. It reloads each app's file in the desktop's Lean three
times and prints how long each took, what Lean said and the apps it
found; tries files it can't reload (Desktop.lean and Main.lean, which
import what the desktop's Lean doesn't, and Clock.lean with an error);
and in an editor alone, Ctrl+R on Clock.lean colours `clockFace` as a
constant, and an unknown name typed on line 14 marks that line. On the
desktop, with real runs, an editor opens Clock.lean, types `NEW ` in
the clock's digits and reloads: the open clock says `NEW 10:08:30`
(`reload-clock.png`); undo brings back the old one; an error reloads
nothing (`reload-error.png`, the line marked and what Lean said under
it). Editor.lean reloaded from the editor opens a new editor beside it
(`reload-editor.png`), and reloaded again replaces that one in place.
Ctrl+C stops a reload. A file with an app the menu doesn't have adds it
to the menu, and Placeholder.lean's apps replace Inspector and Notes.
It times a clock's view and an editor's keystroke, Down and view,
compiled, reloaded, and reloaded without safepoints, and prints RSS
over 40 reloads of Clock.lean and 10 of Editor.lean, each kept for
undo.

[↑ Design](README.md)
