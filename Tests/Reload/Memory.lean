import Tests.Reload.Kit

/-! # `--test`: memory over many reloads

Clock.lean and Editor.lean reloaded again and again from an editor,
each reload kept for undo (docs/design/reloading/reloads-held-by-undo.md). -/

namespace LeanMachine.Tests

-- Memory over many reloads: each one is a step undo can return to, and
-- the apps in the worlds it keeps hold the Lean they came from. Goes on
-- from the desktop `reloadOnDesktop` left.
def reloadMemory (svc : Services) (d : Desktop) (runs : Runs) : IO Unit := do
  let feed := feed svc
  let settle := settle svc
  let ctrlE (ch : Char) : Event := .key (.char ch) { ctrl := true }
  let dkey (k : Key) : Event := .key k {}
  let (d, runs) ← feed d runs [.press 507 300, ctrlE 'o', .text "apps/cl", dkey .enter]
  let (d, runs, _) ← settle d runs
  let mut d := d
  let mut runs := runs
  for (file, n) in [("Clock.lean", 40), ("Editor.lean", 10)] do
    if file == "Editor.lean" then
      (d, runs) ← feed d runs [ctrlE 'o', .text "apps/ed", dkey .enter]
      let (d', runs', _) ← settle d runs
      d := d'; runs := runs'
    let rss0 ← rssMB
    let t0 ← IO.monoNanosNow
    for _ in [0:n] do
      (d, runs) ← feed d runs [ctrlE 'r']
      let (d', runs', _) ← settle d runs
      d := d'; runs := runs'
    let each := ((← IO.monoNanosNow) - t0) / 1000000 / n
    IO.println s!"{n} reloads of {file} from the editor, kept for undo: {each} ms each; RSS \
      {rss0} → {← rssMB} MB; windows {windowList d}"

end LeanMachine.Tests
