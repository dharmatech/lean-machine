import LeanMachine.Win

/-! # The taskbar

A button for each window, in the order they opened, then the hint, then
the count of earlier worlds at the right. The hint gives way when the
buttons would be too narrow for their titles. The world lays it out, so
that the view draws each button where a press finds it. It needs only
the windows (`Taskbar.of`), so it comes before the world. -/

namespace LeanMachine

-- The bar is in front of every window: a window moved partly under it
-- is hidden there, and takes no presses there.
def barY : Float := screenH - barH
def inBar (y : Float) : Bool := y ≥ barY

def barTextSize : Float := 13
def buttonMaxW : Float := 210
def buttonGap : Float := 6
def countW : Float := 150     -- the count of earlier worlds, at the right
def barHint : String := "right-click: apps   ·   Ctrl+Shift+Z: undo   ·   Esc: quit"

-- About how wide `s` is at `size`, in the proportional font. Lean can't
-- measure it (Cairo does, in the shim), so this guesses, erring on the
-- side of room: monospace's 0.6 em a letter, wider than most of the
-- proportional font's letters, and half that for a space.
def approxW (size : Float) (s : String) : Float :=
  monoAdvance size * s.foldl (fun n c => n + if c == ' ' then 0.5 else 1) 0

-- How wide the hint is, with the dot between it and the count.
def hintW : Float := approxW barTextSize (barHint ++ "   ·   ")

structure Taskbar where
  buttons : List (Win × Float)  -- each window, and the left edge of its button
  w : Float                     -- the width of every button
  hint : Bool                   -- whether the hint has room

def Taskbar.of (windows : List Win) : Taskbar :=
  let ws := windows.mergeSort (·.id ≤ ·.id)
  let n := ws.length.toFloat
  let width (hint : Float) : Float :=
    if ws.isEmpty then 0
    else max 0 (min buttonMaxW ((screenW - 16 - countW - hint - buttonGap * (n - 1)) / n))
  -- A dot and room around it, and the widest title.
  let wanted := min buttonMaxW (48 + (ws.map (approxW barTextSize ·.title)).foldl max 0)
  let hint := width hintW ≥ wanted
  let bw := width (if hint then hintW else 0)
  { buttons := ws.zipIdx.map fun (w, i) => (w, 8 + i.toFloat * (bw + buttonGap)),
    w := bw, hint }

-- The window whose button is at (x, y).
def Taskbar.buttonAt (bar : Taskbar) (x y : Float) : Option Win :=
  if !inBar y then none else
  (bar.buttons.find? fun (_, bx) => bx ≤ x && x < bx + bar.w).map (·.1)

end LeanMachine
