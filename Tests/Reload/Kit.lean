import Tests.Kit

/-! # What the reload tests share

A file reloaded on the test's thread (`reloadNow`), Ctrl+R on the
desktop with its runs settled (`reloadOn`), and what the desktop's
windows and editors say. -/

namespace LeanMachine.Tests

-- `src` reloaded in the desktop's Lean as the file at `path`, on this
-- thread: what Lean said, the apps the file defines, and the ms it took.
def reloadNow (svc : Services) (path src : String) :
    IO (Outcome × List (Lean.Name × App) × Nat) := do
  let t0 ← IO.monoNanosNow
  let (o, apps) ← svc.reload path src (← IO.CancelToken.new)
  return (o, apps, ← msSince t0)

-- Ctrl+R, and the events that came back.
def reloadOn (svc : Services) (d : Desktop) (runs : Runs) : IO (Desktop × Runs) := do
  let t0 ← IO.monoNanosNow
  let (d, runs) ← feed svc d runs [.key (.char 'r') { ctrl := true }]
  let (d, runs, seen) ← settle svc d runs
  IO.println s!"    {seen.map (·.showDone)} ({← msSince t0} ms)"
  return (d, runs)

-- What the editor in window `id` says on its status line.
def editorStatus (d : Desktop) (id : Nat) : String :=
  ((((d.now.windows.find? (·.id == id)).map (·.texts)).getD []).find?
    (·.startsWith "LeanMachine/")).getD "?"

-- The windows, each with its id, and the file its app came from if a
-- reload made it.
def windowList (d : Desktop) : List String := d.now.windows.map fun w =>
  s!"{w.id} {w.title}{match w.origin with | some n => s!" ({Editor.lastPart n})" | none => ""}"

end LeanMachine.Tests
