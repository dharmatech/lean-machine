import LeanMachine.Slider
import Tests.Kit

/-! # `--test`: a slider

The slider of docs/explore/slider.md, in a window of its own, dragged
with the pointer and undone; then the same slider made in a REPL
(docs/design/widgets/slider.md). -/

namespace LeanMachine.Tests

-- The slider of docs/explore/slider.md, with what it's set to written
-- under it: a circle as wide as the slider says.
def sizeBox : Rect := ⟨20, 20, 300, Slider.height⟩
def sizer : App :=
  App.of "Size" ({ lo := 1, hi := 80, value := 20 } : Slider) (·.heard sizeBox)
    fun s w h => .group [s.view sizeBox, .text 20 60 13 0x9aa5ce s!"radius {s.value}",
                         .circle (w / 2) (h / 2 + 20) s.value 0x9ece6a]

-- The lines docs/explore/slider.md types into a REPL.
def sliderLines : List String :=
  ["def box : Rect := ⟨20, 20, 300, Slider.height⟩",
   "def look (s : Slider) (w h : Float) : Picture := \
      .group [s.view box, .circle (w / 2) (h / 2 + 20) s.value 0x9ece6a]",
   "launch (App.of \"Size\" ({ lo := 1, hi := 80, value := 20 } : Slider) (·.heard box) look)"]

-- A slider in a window, dragged with the pointer: through the world,
-- past its end and out of the window, and back with one undo. Then
-- the same slider made in a REPL.
def testSlider (c : Canvas) (svc : Services) : IO Unit := do
  IO.println "a slider:"
  let start := steps start [.tick ⟨10, 8, 30⟩]
  -- Where `t` of the way along a window's slider is on the screen.
  let along (d : Desktop) (t : Float) : Float × Float :=
    match winTitled d "Size" with
    | some w => (w.bodyX + sizeBox.x + Slider.knob + t * (sizeBox.w - 2 * Slider.knob),
                 w.bodyY + sizeBox.y + sizeBox.h / 2)
    | none => (0, 0)
  let radius (d : Desktop) : String := says d "Size" "radius"
  let d := steps start [.launch 1 sizer]
  let (x, y) := along d 0.5
  let (x3, _) := along d 0.75
  let (far, _) := along d 2
  let pressed := steps d [.press x y]
  let held := steps pressed [.motion x3 (y + 100)]
  IO.println s!"  pressed halfway: {radius pressed}; moved three quarters along, 100 below: \
    {radius held}"
  render c held.view; shot c "slider.png"
  let let_go := steps held [.motion far y, .release far y]
  IO.println s!"  moved out of the window past the end, and let go: {radius let_go}; \
    a motion then: {radius (steps let_go [.motion x y])}"
  IO.println s!"  undone: {radius (steps let_go [undoKey])}; undo steps made by the drag: \
    {let_go.past.length - d.past.length}"
  -- Made in a REPL, then its knob held near the end.
  let mut d := start
  let mut seen := []
  for line in sliderLines do
    let (d', runs) ← feed svc d {} [.press 120 200, .text line, .key .enter {}]
    let (d', _, ended) ← settle svc d' runs
    d := d'; seen := seen ++ ended
  IO.println s!"  made in a REPL: {seen.map (·.showDone)}; windows {d.now.windows.map (·.title)}"
  let (x, y) := along d 0.25
  let (x9, _) := along d 0.9
  render c (steps d [.press x y, .motion x9 y]).view; shot c "slider-repl.png"

end LeanMachine.Tests
