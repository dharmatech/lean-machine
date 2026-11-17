import LeanMachine.World

/-! # The desktop: the world now, and every world before it

Undo goes back to the previous world. Pure, like the world. -/

namespace LeanMachine

structure Desktop where
  now : World
  past : List World

-- A press or a new window starts a step undo can return to; the motion
-- of a drag doesn't.
def Event.commits : Event → Bool
  | .press .. => true
  | .key k => k == keyN
  | _ => false

def Desktop.record (d : Desktop) (e : Event) : Desktop :=
  let next := d.now.step e
  if e.commits then { now := next, past := (d.now :: d.past).take 500 }
  else { d with now := next }

def Desktop.step (d : Desktop) (e : Event) : Desktop :=
  match e with
  | .key k =>
    if k == keyU then
      match d.past with
      | prev :: rest => { now := prev, past := rest }
      | [] => d
    else d.record e
  | _ => d.record e

-- The desktop the program starts with: four windows and no past.
def start : Desktop :=
  let titles := ["REPL", "Clock", "Inspector", "Notes"]
  { past := [],
    now := { focus := 4, drag := none, nextId := 5, mouseX := 600,
             mouseY := 400,
             windows := titles.zipIdx.map fun (t, i) =>
               { id := i + 1, title := t, x := 80 + 140 * i.toFloat,
                 y := 70 + 90 * i.toFloat, w := 420, h := 260 } } }

end LeanMachine
