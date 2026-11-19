import Tests.Reload.Kit

/-! # `--test`: reloading Boids

Boids.lean reloaded into an open flock from an editor, over its
compiled simulation, whose own files can't be reloaded
(docs/design/reloading/compiled-under-reloaded.md). -/

namespace LeanMachine.Tests

-- Boids from the menu, and an editor on Boids.lean. `NEW ` typed at
-- the start of its status line breaks a check of the file's, so
-- nothing is reloaded; typed before the keys instead, and reloaded, it
-- restarts the open flock with the new code, which frames step.
def reloadBoids (c : Canvas) (svc : Services) : IO Unit := do
  let feed := feed svc
  let settle := settle svc
  let ctrlE (ch : Char) : Event := .key (.char ch) { ctrl := true }
  let dkey (k : Key) : Event := .key k {}
  let boidsSays (d : Desktop) : String :=
    let line := (((d.now.windows.find? (·.title == "Boids")).map (·.texts)).getD []).find?
      (·.contains " boids · ")
    (line.map fun s => " · ".intercalate ((s.splitOn " · ").take 3)).getD "?"
  let (bd, bruns) ← feed start {} [.tick ⟨10, 8, 30⟩, .menu 20 20, menuItem 20 20 5,
    .menu 500 240, menuItem 500 240 2]
  let (bd, bruns, _) ← settle bd bruns
  let (bd, bruns) ← feed bd bruns [.text "apps/boids.lean", dkey .enter]
  let (bd, bruns, _) ← settle bd bruns
  let bedWin := bd.now.focus
  let boidsSrc ← IO.FS.readFile (projectRoot / "LeanMachine/Apps/Boids.lean")
  let lines := boidsSrc.splitOn "\n"
  let statusLine := (lines.findIdx? (·.startsWith "  s!\"{s.flock.size} boids")).getD 0
  let keysAt := ((lines.getD statusLine "").splitOn "r random").head!.length
  let (bd, bruns) ← feed bd bruns ([.key .home { ctrl := true }] ++
    List.replicate statusLine (dkey .down) ++ List.replicate 5 (dkey .right) ++ [.text "NEW "])
  IO.println s!"Boids and an editor on it: windows {windowList bd}; Boids says {boidsSays bd}"
  IO.println s!"  `NEW ` typed at the start of Boids' status line (line {statusLine + 1}), Ctrl+R:"
  let (bd, bruns) ← reloadOn svc bd bruns
  IO.println s!"    Boids says {boidsSays bd}; the editor: {(editorStatus bd bedWin).quote}"
  let (bd, bruns) ← feed bd bruns (List.replicate 4 (dkey .backspace) ++
    List.replicate (keysAt - 5) (dkey .right) ++ [.text "NEW "])
  IO.println s!"  moved to just before its keys, Ctrl+R:"
  let (bd, bruns) ← reloadOn svc bd bruns
  let bd' := [Event.frame 5000, .frame 5016, .frame 5032].foldl Desktop.step bd
  IO.println s!"    windows {windowList bd}; Boids says {boidsSays bd}, after 3 frames \
    {boidsSays bd'}; the editor: {(editorStatus bd bedWin).quote}"
  render c bd'.view; shot c "reload-boids.png"
  let (bd, bruns) ← feed bd bruns [ctrlE 'o', ctrlE 'o', .text "boids/flock", dkey .enter]
  let (bd, bruns, _) ← settle bd bruns
  IO.println s!"  Flock.lean, Ctrl+R:"
  let (bd, _) ← reloadOn svc bd bruns
  IO.println s!"    the editor: {(editorStatus bd bedWin).quote}"

end LeanMachine.Tests
