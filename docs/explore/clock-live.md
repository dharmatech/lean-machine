# Change the clock while it ticks

The clock is `LeanMachine/Apps/Clock.lean`, 55 lines of Lean. Open it
in the editor, change a line, press Ctrl+R, and every clock on the
desktop is the new one, a tenth of a second later.

Ctrl+R reloads the file as it is in the editor; only Ctrl+S writes it.
So try anything: as long as you don't save, the file stays as git has
it, and [putting it back](../use/putting-back.md) is a key or two.

Right-click the desktop and pick Editor. Type `apps/cl` and press
Enter. The line numbers are down the left, and the status line at the
bottom says which line the cursor is on. Make each change below, then
press Ctrl+R and look at the clock.

- **A green second hand.** On line 42, change `0xf7768e` to `0x9ece6a`.
  The dot in the middle, on line 43, is still red: change it too.
- **Long marks only at the quarters.** On line 31, change `i % 5` to
  `i % 15`: 12, 3, 6 and 9 keep their long marks, and the others are
  short.
- **Backwards.** On line 42, put a `-` in front of `t.second`, so it
  reads `(-t.second.toFloat * pi / 30)`. The second hand goes the other
  way round.
- **No seconds in the digits.** On line 14, delete `:{two t.second}`.
- **A new name.** On line 49, change `"Clock"` to `"Time"`. The window's
  title changes, and its button on the taskbar, and the menu: a clock
  you open from it now is the new one too.
- **A mistake.** On line 44, change `16` to `"16"`, a string where Lean
  wants a number. Nothing reloads: the line's number turns red, and
  with the cursor on line 44, Lean's message shows above the status
  line. The clock ticks on as it was. Change it back to `16`.

Ctrl+Shift+Z, right after a Ctrl+R, brings back the clock from before
it. Your changes stay in the editor, so Ctrl+R brings them back again:
press the two in turn to compare.

## Other files you can change

- `apps/placeholder.lean` is Inspector and Notes, both made by
  `placeholder`. On line 43, change the dots' yellow, `0xe0af68`, and
  both apps change.
- `apps/boids.lean`: [Change Boids while it flies](boids-live.md).
- `apps/repl.lean` and `apps/editor.lean` are the REPL and the editor
  themselves. They take a second or so to reload. An editor that
  reloads its own file keeps going, and the new one opens beside it.

Every other file is built into the desktop, and Ctrl+R on one says so:
to change it, rebuild the desktop and start it again
([Reloading an app](../use/reloading.md)).

## Putting it back

- **Undo:** Ctrl+Shift+Z right after Ctrl+R.
- **The file as git has it:** Ctrl+O, Ctrl+O again to leave your
  changes, open the file again, and Ctrl+R.
- **Everything:** quit with Esc and start Lean Machine again.

If you pressed Ctrl+S, see [Putting a file back](../use/putting-back.md).

## Where next

- [Pictures, from the REPL](pictures.md): the same kinds of picture as
  the clock's face, made in the REPL.
- [No state carries over](../design/reloading/no-state-carries-over.md):
  why a reloaded app starts afresh.

[↑ Explore](README.md)
