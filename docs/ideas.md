# Ideas for next

- Runs the world declares instead of requests: the world would keep
  the runs it waits for, and the loop would start and stop threads to
  match the world now, so undo would stop or restart work along with
  the rest. Pure work can be run again safely; evaluation that changes
  the environment can't.
- Guard the steps and views of apps made in the REPL, on the main
  thread: they have safepoints now, so a watchdog could raise a flag
  for them after a few frames' time.
- Definitions shared between REPLs, or a REPL opened from another's Lean.
- Errors pointed at with a caret under the line, not a column number.
- Completion that needs elaboration: a field or function after a term
  (`xs.ma`) or a constructor by the type expected (`.cir`). Elaborate
  the line up to the cursor in a run, with info trees on, and ask Lean's
  own completion; Tab would answer when the run ends.
- Colours by meaning once a line is entered: it's elaborated then, so
  with info trees on, variables, functions and types could be told
  apart as Lean's editor does.
- Tab again to go through what's offered, or a click on an offered name.
- The REPL: scroll back through the transcript (PageUp, the wheel),
  place the cursor with a click, Ctrl+A and Ctrl+E, and keep the cursor
  in view when a line is taller than the window.
- Undo goes back a press at a time, so it also undoes everything typed
  since the last press. An app could say which of its events make a step
  worth returning to (Enter in a REPL, say).
- Right-click for apps too, perhaps a window menu, now that the right
  button always opens the desktop's menu.
- Windows: tile and cascade, as Schevana's desktop/arrange.ss does.
  Each computes rectangles for the windows that aren't minimized
  (`World.visible`) and calls `World.place`. Then keys to go from window
  to window (`World.focusOn`), a window menu on a taskbar button's right
  click, and closing a window giving the focus to the frontmost one left,
  as minimizing does.
- Resizing: the pointer's shape over an edge (SDL's system cursors,
  through the shim); a minimum size an app asks for, not only the
  desktop's; keys to move and resize the focused window.
- Reloading: hand an app's state to its new code, as plain data;
  reload an app made of a folder of modules, interpreted (elaborate
  them in import order; slow for Boids' simulation, which is compiled
  in instead:
  [A compiled simulation under a reloaded app](design/reloading/compiled-under-reloaded.md));
  go to the next marked line; reload on save; keep fewer reloads for
  undo than other steps.
- The editor: read only the lines in view, and the rest later; select,
  copy and cut (paste and selecting are in); a drag held past the
  edge that goes on scrolling; search; undo a keystroke at a time; open a file from
  the REPL; warn before Esc quits with changes not saved.
- Measure proportional text in the view, for layout that wraps (Notes)
  and for the taskbar, which guesses
  ([The taskbar guesses how wide text is](design/drawing/guessing-text-widths.md)).
  Monospace text can be measured already.
- Display scaling and a resizable window.
- Boids: its rules in a window of their own, as Schevana's has, once a
  window can open another and send it messages; buttons for R, D and S;
  draw a flock's lines and dots as one path each
  ([At 1000 boids, drawing costs more than the step](design/boids/drawing-costs-more.md));
  a grid of cells, so a boid looks only at its neighbors' cells.

[↑ Lean Machine](../README.md)
