import LeanMachine.App

/-! # A placeholder: stands in for an app not written yet

A press drops a dot where it lands, in the app's own coordinates, so the
dot showing up under the pointer says the desktop got them right. -/

namespace LeanMachine

def placeholder (title : String) : App :=
  -- the dots, newest first
  App.of title ([] : List (Float × Float))
    (fun dots e => match e with
      | .press x y => some ((x, y) :: dots)
      | _ => none)
    (fun dots w h => .group (
      [.text 12 22 13 0x9aa5ce s!"{title} isn't written yet",
       .text 12 42 13 0x565f89 "click here to drop a dot"] ++
      (match dots with
       | (x, y) :: _ =>
         [.text 12 (h - 12) 12 0x565f89
           s!"last dot at {x.toUInt32}, {y.toUInt32} of {w.toUInt32} × {h.toUInt32}"]
       | [] => []) ++
      dots.map fun (x, y) => .circle x y 5 0xe0af68))

end LeanMachine
