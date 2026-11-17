import LeanMachine.App

/-! # A placeholder: stands in for an app not written yet

A press drops a dot where it lands, in the app's own coordinates, so the
dot showing up under the pointer says the desktop got them right. It
shows what it was typed and the last key it heard, with its modifiers, so
the keyboard can be checked the same way. -/

namespace LeanMachine

structure Placeholder where
  dots : List (Float × Float) := []   -- newest first
  typed : String := ""                -- the last 40 characters typed
  heard : String := ""                -- the last key, as "Ctrl+Shift+N"

def placeholder (title : String) : App :=
  App.of title ({} : Placeholder)
    (fun s e => match e with
      | .press x y => some { s with dots := (x, y) :: s.dots }
      | .text t =>
        let typed := s.typed ++ t
        some { s with typed := typed.drop (typed.length - 40) |>.toString }
      | .key k m => some { s with heard := k.show m }
      | _ => none)
    (fun s w h => .group (
      [.text 12 22 13 0x9aa5ce s!"{title} isn't written yet",
       .text 12 42 13 0x565f89 "click here to drop a dot, or type",
       .mono 12 70 14 0xc0caf5 s!"typed: {s.typed}",
       .mono 12 90 14 0xc0caf5 s!"key:   {s.heard}"] ++
      (match s.dots with
       | (x, y) :: _ =>
         [.text 12 (h - 12) 12 0x565f89
           s!"last dot at {x.toUInt32}, {y.toUInt32} of {w.toUInt32} × {h.toUInt32}"]
       | [] => []) ++
      s.dots.map fun (x, y) => .circle x y 5 0xe0af68))

end LeanMachine
