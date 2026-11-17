import LeanMachine.World
import LeanMachine.Apps.Placeholder
import LeanMachine.Apps.Clock
import LeanMachine.Apps.Repl

/-! # The desktop: the world now, and every world before it

Undo goes back to the previous world. Pure, like the world. -/

namespace LeanMachine

structure Desktop where
  now : World
  past : List World

-- `next`, as a step undo can return from. The world kept for undo has
-- its menu closed, so undo never brings a menu back.
def Desktop.commit (d : Desktop) (next : World) : Desktop :=
  { now := next, past := ({ d.now with menu := none } :: d.past).take 500 }

def Desktop.undo (d : Desktop) : Desktop :=
  match d.past with
  | prev :: rest => { now := prev, past := rest }
  | [] => d

-- Ctrl+Shift+Z undoes. Whether anything else starts a step undo can
-- return to is the world's to say (`World.commits`): a press that does
-- something.
def Desktop.step (d : Desktop) (e : Event) : Desktop :=
  match e with
  | .key k m =>
    if desktopKey 'z' k m then d.undo else { d with now := d.now.step e }
  | _ =>
    let next := d.now.step e
    if d.now.commits e then d.commit next else { d with now := next }

-- What the menu opens.
def catalog : List App :=
  [clock, repl, placeholder "Inspector", placeholder "Notes"]

-- The desktop the program starts with: four windows, opened as the menu
-- opens them, each lower and to the right of the last, and no past.
def start : Desktop :=
  let empty : World :=
    { windows := [], focus := 0, drag := none, menu := none, catalog,
      time := ⟨0, 0, 0⟩, nextId := 1, mouseX := 600, mouseY := 400 }
  let apps := [repl, clock, placeholder "Inspector", placeholder "Notes"]
  { past := [],
    now := apps.zipIdx.foldl (init := empty) fun world (app, i) =>
      world.launch app (80 + 140 * i.toFloat) (70 + 90 * i.toFloat) }

end LeanMachine
