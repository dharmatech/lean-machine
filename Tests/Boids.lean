import Tests.Kit

/-! # `--test`: Boids

Boids from the menu: frames, the rules' sliders, H, Space and
minimizing, and what a frame costs at 150 boids and at 1000
(docs/use/boids.md). -/

namespace LeanMachine.Tests

-- Boids from the menu: keys, frames, minimizing, and what a frame costs
-- at 150 boids and at 1000.
def testBoids (c : Canvas) : IO Unit := do
  IO.println "Boids:"
  let key (k : Key) : Event := .key k {}
  let frames (from_ n : Nat) : List Event := (List.range n).map fun i => .frame (from_ + 16 * i)
  let d := steps start [.tick ⟨10, 8, 30⟩, .menu 20 20, menuItem 20 20 5]
  IO.println s!"  from the menu: windows {d.now.windows.map (·.title)}, focus on {focused d}, \
    animates {d.now.animating}"
  let d := steps d (frames 1000 60)
  render c d.view; shot c "boids.png"
  -- The rules: separation's slider dragged three quarters along, a weight
  -- on a cube, with the pointer below its row, the flock flying on.
  let rowSays (d : Desktop) (label : String) : String :=
    let texts := ((winTitled d "Boids").map (·.texts)).getD []
    ((texts.dropWhile (· != label)).drop 1).headD "none"
  let along (r : Boids.Row) (t : Float) : Float × Float :=
    match winTitled d "Boids" with
    | some w =>
      let b := Boids.sliderBox w.bodyW (Boids.Row.all.idxOf r)
      (w.bodyX + b.x + Slider.knob + t * (b.w - 2 * Slider.knob), w.bodyY + b.y + b.h / 2)
    | none => (0, 0)
  let (x, y) := along (.setting .separation) 0
  let (x3, _) := along (.setting .separation) 0.75
  let held := steps d ([.press x y, .motion x3 (y + 40)] ++ frames 2000 60)
  IO.println s!"  separation at first {rowSays d "separation"}; dragged three quarters along, \
    40 below, 60 frames: {rowSays held "separation"}"
  render c held.view; shot c "boids-rules.png"
  let let_go := steps held [.release x3 (y + 40)]
  IO.println s!"  let go, then undone: {rowSays (steps let_go [undoKey]) "separation"}, \
    {let_go.past.length - d.past.length} undo step"
  let hidden := steps let_go [key (.char 'h')]
  IO.println s!"  H: rows shown {rowSays hidden "separation" != "none"}; a press on the \
    slider's place changes it: {rowSays (steps hidden [.press x y, key (.char 'h')]) "separation" != rowSays let_go "separation"}"
  render c (steps hidden (frames 3000 60)).view; shot c "boids-no-rules.png"
  let paused := steps d [key (.char ' ')]
  IO.println s!"  Space: animates {paused.now.animating}; again: \
    {(steps paused [key (.char ' ')]).now.animating}"
  render c paused.view; shot c "boids-paused.png"
  let hidden := steps d [.key (.char 'h') ctrlShift]
  IO.println s!"  minimized: animates {hidden.now.animating}"
  -- What a frame costs: the step (a frame to the world, whose Boids
  -- steps its flock), the view, and drawing it.
  let cost (d : Desktop) (label : String) : IO Unit := do
    let stepUs ← usPer 50 fun i => do
      if !(d.step (.frame (5000 + 16 * i))).now.animating then IO.println "?"
    let viewUs ← usPer 50 fun i =>
      match (if i == 50 then start else d).view with
      | .group [] => IO.println "?"
      | _ => pure ()
    let drawUs ← usPer 50 fun _ => render c d.view
    IO.println s!"  {label}: a frame's step {stepUs} µs, the desktop's view {viewUs} µs, \
      drawn in {drawUs} µs"
  cost d "150 boids"
  let many := steps d (List.replicate 17 (key .up) ++ frames 2000 60)
  render c many.view; shot c "boids-1000.png"
  cost many "1000 boids"

end LeanMachine.Tests
