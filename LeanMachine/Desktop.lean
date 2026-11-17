import LeanMachine.World
import LeanMachine.Apps.Placeholder
import LeanMachine.Apps.Clock

/-! # The desktop: the world now, and every world before it

Undo goes back to the previous world. Pure, like the world. -/

namespace LeanMachine

structure Desktop where
  now : World
  past : List World

-- `next` as a step undo can return from.
def Desktop.commit (d : Desktop) (next : World) : Desktop :=
  { now := next, past := (d.now :: d.past).take 500 }

def Desktop.undo (d : Desktop) : Desktop :=
  match d.past with
  | prev :: rest => { now := prev, past := rest }
  | [] => d

-- A press or a new window starts a step undo can return to; motion, a
-- release and the keys an app hears don't.
def Desktop.step (d : Desktop) (e : Event) : Desktop :=
  match e with
  | .key k =>
    if k == keyU then d.undo
    else if k == keyN then
      d.commit (d.now.launch (placeholder s!"Window {d.now.nextId}"))
    else { d with now := d.now.step e }
  | .press .. => d.commit (d.now.step e)
  | _ => { d with now := d.now.step e }

-- The desktop the program starts with: four windows and no past. Each is
-- an app and the window's width and height.
def start : Desktop :=
  let apps : List (App × Float × Float) :=
    [(placeholder "REPL", 420, 260), (clock, 236, 290),
     (placeholder "Inspector", 420, 260), (placeholder "Notes", 420, 260)]
  { past := [],
    now := { focus := 4, drag := none, nextId := 5, mouseX := 600,
             mouseY := 400,
             windows := apps.zipIdx.map fun ((app, w, h), i) =>
               { id := i + 1, app, x := 80 + 140 * i.toFloat,
                 y := 70 + 90 * i.toFloat, w, h } } }

end LeanMachine
