import Tests.Reload.Kit

/-! # `--test`: what reloaded code costs

A clock, an editor and Boids, compiled against reloaded, and reloaded
without safepoints (docs/design/reloading/interpreted.md). -/

namespace LeanMachine.Tests

-- What reloaded code costs: it runs in Lean's interpreter, and starts
-- every function at a safepoint, which nothing can stop on the loop's
-- thread yet. `made` has the apps `reloadFiles` reloaded.
def reloadCosts (c : Canvas) (svc : Services) (made : List (Lean.Name × App)) : IO Unit := do
  let key (k : Key) : AppEvent := .key k {}
  let madeApp (n : Lean.Name) : App := ((made.find? (·.1 == n)).map (·.2)).getD default
  IO.println "costs, compiled and reloaded:"
  let raw (file : String) : IO (App × Nat) := do
    let src ← IO.FS.readFile (projectRoot / s!"LeanMachine/Apps/{file}")
    let (_, apps, t) ← reloadNow svc file
      (src.replace "namespace LeanMachine" "set_option leanMachine.safepoints false\nnamespace LeanMachine")
    return ((apps.head?.map (·.2)).getD default, t)
  let (rawClock, rawClockMs) ← raw "Clock.lean"
  let (rawEditor, rawEditorMs) ← raw "Editor.lean"
  IO.println s!"  reloaded without safepoints: Clock.lean in {rawClockMs} ms, Editor.lean in {rawEditorMs} ms"
  let atTen := fun (a : App) => ((a.step (.tick ⟨10, 8, 30⟩)).map (·.1)).getD a
  for (name, a) in [("compiled", clock), ("reloaded", madeApp ``clock),
                    ("reloaded without safepoints", rawClock)] do
    let a := atTen a
    let us ← usPer 500 fun i => do
      if (a.view (230 + (i % 2).toFloat) 259).texts.isEmpty then IO.println "?"
    let drawUs ← usPer 200 fun i => do render c (a.view (230 + (i % 2).toFloat) 259)
    IO.println s!"  a {name} clock: the view in {us} µs, drawn in {drawUs} µs"
  for (name, a) in [("compiled", editor), ("reloaded", madeApp ``editor),
                    ("reloaded without safepoints", rawEditor)] do
    let a ← ([.tick ⟨10, 8, 30⟩, .text "apps/repl", key .enter] ++ List.replicate 120 (key .down)).foldlM
      (appNow svc) a
    let keyUs ← usPer 2000 fun i => do
      if let some (a', _) := a.step (.text (Char.ofNat (97 + i % 26)).toString) then
        if a'.title.isEmpty then IO.println "?"
    let downUs ← usPer 2000 fun i => do
      if let some (a', _) := a.step (key (if i == 100000 then .up else .down)) then
        if a'.title.isEmpty then IO.println "?"
    let viewUs ← usPer 200 fun i => do
      if (a.view (editorSize.1 + (i % 2).toFloat) editorSize.2).monos == 0 then IO.println "?"
    IO.println s!"  a {name} editor on {a.title}, line 121: a keystroke {keyUs} µs, Down {downUs} µs, \
      the view {viewUs} µs"
  -- Boids' step calls the compiled simulation either way; its view is
  -- the app's own code.
  let heard (a : App) (e : AppEvent) : App := ((a.step e).map (·.1)).getD a
  for (name, a) in [("compiled", boids), ("reloaded", madeApp ``boids)] do
    let mut a := (List.range 5).foldl (fun a i => heard a (.frame (1000 + 16 * i))) a
    let mut said := []
    for n in [150, 1000] do
      if n == 1000 then a := (List.replicate 17 (key .up)).foldl heard a
      let at_ := a
      let stepUs ← usPer 20 fun i => do
        if !(heard at_ (.frame (2000 + 16 * i))).animating then IO.println "?"
      let viewUs ← usPer 20 fun i => do
        if (at_.view (760 + (i % 2).toFloat) 544).texts.isEmpty then IO.println "?"
      said := said ++ [s!"at {n} boids a frame's step {stepUs} µs, the view {viewUs} µs"]
    IO.println s!"  a {name} Boids: {", ".intercalate said}"

end LeanMachine.Tests
