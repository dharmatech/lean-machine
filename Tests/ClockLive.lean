import Tests.Reload.Kit

/-! # `--test`: the clock changed while it ticks

The changes docs/explore/clock-live.md makes to Clock.lean, each on the
line the page names (the test fails if the line hasn't the text), made
one after another and reloaded after each; the mistake, which reloads
nothing; and the dots of Placeholder.lean. Then, on the desktop, an
editor on Clock.lean with all the changes pasted in, Ctrl+R
(`clock-live.png`), and the page's ways of putting it back: undo, Ctrl+R
again, then Ctrl+O twice, the file opened again, and Ctrl+R. The file on
disk never changes. -/

namespace LeanMachine.Tests

-- `src` with `old` on line `line` (from 1) made `new`; `old` must be
-- there once.
def editLine (src : String) (line : Nat) (old new : String) : IO String := do
  let ls := src.splitOn "\n"
  let some l := ls[line - 1]? | throw (IO.userError s!"no line {line}")
  unless (l.splitOn old).length == 2 do
    throw (IO.userError s!"line {line} hasn't `{old}` once: {l.quote}")
  return String.intercalate "\n" (ls.set (line - 1) (l.replace old new))

-- The page's changes, in its order: what each is, and its line, what's
-- there and what it becomes.
def clockEdits : List (String × Nat × String × String) :=
  [("a green second hand", 42, "0xf7768e", "0x9ece6a"),
   ("its dot green too", 43, "0xf7768e", "0x9ece6a"),
   ("long marks at the quarters", 31, "i % 5", "i % 15"),
   ("backwards", 42, "(t.second", "(-t.second"),
   ("no seconds in the digits", 14, ":{two t.second}", ""),
   ("a new name", 49, "\"Clock\"", "\"Time\"")]

def testClockLive (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "the clock changed while it ticks (docs/explore/clock-live.md):"
  let path := "LeanMachine/Apps/Clock.lean"
  let original ← IO.FS.readFile (projectRoot / path)
  let mut src := original
  for (what, line, old, new) in clockEdits do
    src ← editLine src line old new
    let (o, apps, ms) ← reloadNow svc path src
    IO.println s!"  {what}, line {line}: {o.show}; apps {apps.map (·.2.title)}, {ms} ms"
  let edited := src
  let (o, apps, _) ← reloadNow svc path (← editLine src 44 "16" "\"16\"")
  IO.println s!"  a mistake, line 44: {o.show}; {apps.length} apps"
  let ph := "LeanMachine/Apps/Placeholder.lean"
  let (o, apps, _) ← reloadNow svc ph
    (← editLine (← IO.FS.readFile (projectRoot / ph)) 43 "0xe0af68" "0x7dcfff")
  IO.println s!"  Placeholder.lean, the dots on line 43: {o.show}; apps {apps.map (·.2.title)}"
  -- On the desktop: an editor from the menu, on Clock.lean, with the
  -- whole file replaced by the changed one, as if typed.
  let ctrl (ch : Char) : Event := .key (.char ch) { ctrl := true }
  let (d, runs) ← feed svc start {} [.tick ⟨10, 8, 30⟩, .menu 500 100, menuItem 500 100 2]
  let (d, runs, _) ← settle svc d runs
  let (d, runs) ← feed svc d runs [.text "apps/cl", .key .enter {}]
  let (d, runs, _) ← settle svc d runs
  let ed := d.now.focus
  let titles (d : Desktop) : String :=
    s!"windows {d.now.windows.map (·.title)}, menu {d.now.catalog.map (·.2.title)}"
  let (d, runs) ← feed svc d runs [ctrl 'a', .paste edited]
  IO.println "  every change pasted into an editor, Ctrl+R:"
  let (d, runs) ← reloadOn svc d runs
  IO.println s!"    {titles d}"
  render c d.view; shot c "clock-live.png"
  let (d, runs) ← feed svc d runs [undoKey]
  IO.println s!"  undo: {titles d}; the editor: {(editorStatus d ed).quote}"
  IO.println "  Ctrl+R again:"
  let (d, runs) ← reloadOn svc d runs
  IO.println s!"    {titles d}"
  let (d, runs) ← feed svc d runs [ctrl 'o']
  IO.println s!"  Ctrl+O: {(editorStatus d ed).quote}"
  let (d, runs) ← feed svc d runs [ctrl 'o', .text "apps/cl", .key .enter {}]
  let (d, runs, _) ← settle svc d runs
  IO.println s!"  Ctrl+O again, the file opened again: {(editorStatus d ed).quote}; Ctrl+R:"
  let (d, _) ← reloadOn svc d runs
  IO.println s!"    {titles d}"
  IO.println s!"  Clock.lean on disk as it was: {(← IO.FS.readFile (projectRoot / path)) == original}"

end LeanMachine.Tests
