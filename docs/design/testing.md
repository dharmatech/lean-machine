# What `--test` checks

`--test` puts what it writes in `.lake/test/`, wherever it runs from;
git ignores it, and it can be deleted at any time. Its code is in
`Tests/`, a module for each test, with what they share in
`Tests/Kit.lean`; `Tests.lean` runs them all, in the order below
([How it's built](modules.md)). It writes
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

Then the screen resized. It prints where each window is on the start
desktop. On a 900 × 600 screen with the menu open at the bottom right,
Notes is pushed in, the menu is kept on the screen and the taskbar's
hint gives way (`screen-small.png`). On a 1600 × 1000 screen nothing
moves (`screen-large.png`). Notes, maximized and then put on 900 × 600,
fills the new desktop and hears its size; its box restores it inside
the smaller screen. Clock is maximized and the screen made smaller,
which makes no undo step; undo restores Clock and keeps the 900 × 600
screen, and going back to 1280 × 800 moves nothing. Notes dragged 140
pixels off the right edge is still 140 off on 900 × 600. On 400 × 300,
windows stop at the left and top edges.

Then frames. The start desktop doesn't animate. A spinner (a line that
the frames it hears turn, the last frame's time in its title) opens as
a run in the REPL would open it. After frames at 1000 and 1017 ms, its
title says 1017, and the frames made no undo step (`frames.png`).
Minimized, it hears no frames, and the desktop doesn't animate; undone,
it hears them again. Last, the three lines of
[A spinner, made in the REPL](../explore/spinner.md) are typed into a
REPL, which opens a spinner that animates (`frames-repl.png`).

Then Boids, opened from the menu: it's focused, and the desktop
animates. After 60 frames it's drawn, its rules beside it
(`boids.png`). Separation's slider is pressed at its start and dragged
three quarters along, 40 pixels below its row: 0.4219, a weight on a
cube; the flock flies on through 60 frames with the knob held
(`boids-rules.png`). Let go and undone, separation is 0.0010 again, in
one undo step. H hides the rules, and a press where the slider was
changes nothing (`boids-no-rules.png`, the field the whole body). Space pauses it,
and the desktop stops animating, until Space again
(`boids-paused.png`); minimized, it doesn't animate either. It times a
frame at 150 boids and, after Up 17 times and 60 more frames, at 1000
(`boids-1000.png`): the step (the world hearing the frame), the
desktop's view, and drawing it.

Then a slider, from 1 to 80, in a window as a run in the REPL would
open it. A press halfway along its track sets it to 40.5, and a motion
three quarters along, 100 pixels below the track, to 60.25
(`slider.png`, the knob held). A motion out of the window, past the
track's end, stops it at 80, and after the release a motion changes
nothing. One undo takes back the whole drag, which made one step. Last,
the three lines of [A slider, made in the REPL](../explore/slider.md)
are typed into a REPL, which opens the slider, and its knob is dragged
near the end (`slider-repl.png`).

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

Then pasting, with the text handed over as a paste event. An editor
alone takes two lines, with Windows line ends, a tab and a comment
across them, at the start of a scratch file's second line, and prints
each line with what it leaves open; then one line at the end of a
line, and a paste into the list of files. A REPL alone takes a line
with blank lines around it and evaluates it, then a block of four
lines: it prints where Up, End, Home and Down put the cursor, what
Enter evaluates, the block recalled by Up and walked to its first line,
the line before it, a block typed with Shift+Enter whose error says its
line, and the rows a view 200 high shows of 30 lines with the cursor on
the first. On the desktop, "1 + " typed and "2" pasted into the REPL,
undone back to "1 + "; a snippet pasted into Clock.lean
(`paste-editor.png`), its `•` gone after undo; and the REPL maximized,
a `structure` and an `#eval` pasted and evaluated, and a `def` pasted
with the cursor moved up into it (`paste-repl.png`).

Then selecting in the editor, alone on a scratch file: it prints what's
selected, and where the cursor is, after Shift with Right, Down, End
and Up and Left from the end of a line; a move without Shift; text,
Enter and a paste typed over a selection, and Backspace on it; Ctrl+A
and Delete; a drag from a press, a motion after the release and a
press. On the desktop it drags down seven lines of Clock.lean
(`select-editor.png`), then from the same line to under the window,
where five motions scroll it five lines.

Then copying and cutting, in an editor alone: it prints what Ctrl+C,
Ctrl+Shift+C and Ctrl+X ask for, and the note they leave, with two
lines selected, with nothing selected, and with nothing selected during
a reload (Ctrl+C stops it); then a cut, and what it copied pasted at
the end of the file. On the desktop, lines 12 to 18 of Clock.lean
selected by a drag and copied through the loop (`copy-editor.png`).

Then selecting and copying in the REPL, alone, its lines evaluated at
once: it prints what drags select over `144`, over part of a line
entered, from that line's prompt to the end of its output, over a
block of two lines alone and among the entries around it, over a list
that wraps onto two rows (one line), from the end of the list into the
line being typed, and from the last line entered to below the rows. It
prints what Ctrl+C and Ctrl+Shift+C ask for with something selected
and with nothing, what typing does to a selection, and Ctrl+C twice
with a run going: a copy, then a stop. On the desktop, three lines are
typed into the REPL, a drag goes from `144` to the end of the list
(`copy-repl.png`), and Ctrl+C asks for a copy; again, it asks for
nothing, and clears the line. Then clicks: in the REPL alone, after the
`t` of a line being typed, and "x" typed there; before the second line
of a block in the line, and "2 * " typed; a drag in the line, which
selects and leaves the cursor where it pressed; a click on what Tab
offered, which leaves the line and the offer; and a click below a
lone line, which puts the cursor at its end. On the desktop, a click
before `xyz` in "abc xyz" (`repl-click.png`) and "X " typed there.

Then scrolling the REPL back. A REPL alone evaluates twenty lines, more
than its view holds, and it prints the first and last rows shown, and
whether the cursor is: following the newest rows, the wheel a step back
and 100 more, a step on from the top and from a step back, half a step
twice, PageUp and PageDown, Shift+PageUp twice, a run that ends while
it's scrolled back, and a key typed then. It prints what Ctrl+C copies
after a drag up at the top, and where drags past the top and the bottom
of the rows leave the view and how many lines they select. On the
desktop the same lines go into the REPL, the wheel scrolls it to the
top and a step on, a drag goes from `222` to `333` (`repl-scroll.png`)
and Ctrl+C asks for a copy; then "1" typed brings back the line.

Then reloading. It reloads each app's file in the desktop's Lean three
times and prints how long each took, what Lean said and the apps it
found; tries files it can't reload (Desktop.lean and Main.lean, which
import what the desktop's Lean doesn't, Boids' Flock.lean, which it
imported, and Clock.lean with an error); evaluates a line that steps
Boids' demo flock with the compiled simulation;
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
Then Boids from the menu and an editor on Boids.lean: `NEW ` typed at
the start of its status line breaks one of the file's checks, so
nothing is reloaded; typed before the keys instead, the open flock
restarts with it and frames step it (`reload-boids.png`). Ctrl+R on
Flock.lean is refused. It times a clock's view and an editor's
keystroke, Down and view, compiled, reloaded, and reloaded without
safepoints, and a frame's step and view of Boids, compiled and
reloaded, at 150 boids and at 1000, and prints RSS
over 40 reloads of Clock.lean and 10 of Editor.lean, each kept for
undo.

[↑ Design](README.md)
