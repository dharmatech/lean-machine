import Tests.Reload.Kit

/-! # `--test`: reloading on the desktop

With real runs: Clock.lean edited and reloaded into the open clock from
an editor, undone, an error, Editor.lean reloaded from an editor, a
reload stopped, and a new app (docs/design/reloading/README.md). -/

namespace LeanMachine.Tests

-- A small app in a file of its own, which the menu doesn't have.
def helloSrc : String := "import LeanMachine.App

namespace LeanMachine

def hello : App :=
  App.of \"Hello\" (0 : Nat) (fun n e => match e with | .press .. => some (n + 1) | _ => none)
    (fun n w h => .textIn 0 0 w h 20 .center 0x9ece6a s!\"hello, {n} presses\") (size := (300, 120))

end LeanMachine
"

-- The desktop, with real runs: an app launched from the REPL, then an
-- editor from the menu, right of the clock, on Clock.lean, reloading
-- it and Editor.lean; a new app (`helloSrc`), and the placeholders'
-- apps from `made`. The desktop and its runs, for `reloadMemory`.
def reloadOnDesktop (c : Canvas) (svc : Services) (made : List (Lean.Name × App)) :
    IO (Desktop × Runs) := do
  let feed := feed svc
  let settle := settle svc
  let ctrlE (ch : Char) : Event := .key (.char ch) { ctrl := true }
  let dkey (k : Key) : Event := .key k {}
  -- The REPL can't name the apps, but finds them in the menu's catalog.
  let launchLine := "do launch ((← world).catalog.lookup `LeanMachine.clock).get!"
  let (d, runs) ← feed start {} ([.press 120 200, .text launchLine, dkey .enter])
  let (d, _, seen) ← settle d runs
  IO.println s!"a REPL line, {launchLine}: {seen.map (·.showDone)}; windows {d.now.windows.map (·.title)}"
  let (d, runs) ← feed start {} [.tick ⟨10, 8, 30⟩, .menu 500 100, menuItem 500 100 2]
  let (d, runs, _) ← settle d runs
  let (d, runs) ← feed d runs [.text "apps/cl", dkey .enter]
  let (d, runs, _) ← settle d runs
  let edWin := d.now.focus
  let win (d : Desktop) (id : Nat) : Option Win := d.now.windows.find? (·.id == id)
  let clockSays (d : Desktop) : List String :=
    d.now.windows.filterMap fun w => if w.title == "Clock" then w.texts.getLast? else none
  IO.println s!"on the desktop: windows {windowList d}; the clock says {clockSays d}"
  IO.println "  Ctrl+R on Clock.lean as it is:"
  let (d, runs) ← reloadOn svc d runs
  IO.println s!"    windows {windowList d}; the clock says {clockSays d}; {d.past.length} earlier worlds"
  -- A press after `s!"` on line 14: the editor's body is at (503, 128).
  let (d, runs) ← feed d runs [.press (503 + Editor.textX + monoAdvance edFont * 5 + 1)
    (128 + Editor.rowY 13 + 9), .text "NEW "]
  IO.println "  `NEW ` typed in the clock's digits, Ctrl+R:"
  let (d, runs) ← reloadOn svc d runs
  IO.println s!"    the clock says {clockSays d}; the editor: {(editorStatus d edWin).quote}"
  render c d.view; shot c "reload-clock.png"
  let (d, runs) ← feed d runs [.key (.char 'z') ctrlShift]
  IO.println s!"  undo: the clock says {clockSays d}; the editor: {(editorStatus d edWin).quote}"
  let (d, runs) ← feed d runs [.text "{oops} "]
  IO.println "  `{oops} ` typed after it, Ctrl+R:"
  let (d, runs) ← reloadOn svc d runs
  IO.println s!"    the clock says {clockSays d}; the editor: {(editorStatus d edWin).quote}"
  render c d.view; shot c "reload-error.png"
  let (d, runs) ← feed d runs (List.replicate 7 (dkey .backspace))
  IO.println "  `{oops} ` deleted, Ctrl+R:"
  let (d, runs) ← reloadOn svc d runs
  IO.println s!"    the clock says {clockSays d}"
  -- Editor.lean, reloaded from the editor: a new editor opens beside it.
  let (d, runs) ← feed d runs [ctrlE 'o', ctrlE 'o', .text "apps/ed", dkey .enter]
  let (d, runs, _) ← settle d runs
  IO.println s!"  Editor.lean, Ctrl+R:"
  let (d, runs) ← reloadOn svc d runs
  IO.println s!"    windows {windowList d}; focus {d.now.focus}"
  render c d.view; shot c "reload-editor.png"
  -- Again from the first editor, which still shows a strip at its left:
  -- the new one is replaced, in place.
  let (d, runs) ← feed d runs [.press 507 300]
  IO.println s!"  the first editor again ({(win d edWin).map (·.title)}), Ctrl+R:"
  let (d, runs) ← reloadOn svc d runs
  IO.println s!"    windows {windowList d}"
  -- Ctrl+C 100 ms into a reload stops it.
  let (d, runs) ← feed d runs [ctrlE 'r']
  IO.sleep 100
  let t0 ← IO.monoNanosNow
  let (d, runs) ← feed d runs [ctrlE 'c']
  let (d, runs, seen) ← settle d runs
  IO.println s!"  Ctrl+R, then Ctrl+C 100 ms later: {seen.map (·.showDone)}, {← msSince t0} ms after \
    Ctrl+C; the editor: {(editorStatus d edWin).quote}"
  -- A new app goes at the end of the menu, and opens beside the editor;
  -- the placeholders' file replaces Inspector and Notes in place.
  let (o, hello, _) ← reloadNow svc "Hello.lean" helloSrc
  let d := d.step (.reload edWin hello)
  IO.println s!"  Hello.lean ({o.show}): the menu {d.now.catalog.map (·.2.title)}; windows {windowList d}"
  let placeholders := made.filter fun (n, _) => n == ``inspector || n == ``notes
  let d := d.step (.reload edWin placeholders)
  IO.println s!"  Placeholder.lean's apps: windows {windowList d}, {d.past.length} earlier worlds"
  return (d, runs)

end LeanMachine.Tests
