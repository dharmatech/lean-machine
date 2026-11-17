/-! # The world: the windows, the pointer, and what an event does to them

Pure: `World.step` makes a new world and changes nothing. -/

namespace LeanMachine

def screenW : Float := 1280
def screenH : Float := 800
def titleH : Float := 28

inductive Event where
  | quit
  | press (x y : Float)
  | release (x y : Float)
  | motion (x y : Float)
  | key (code : UInt32)

def keyEscape : UInt32 := 27
def keyN : UInt32 := 'n'.toNat.toUInt32
def keyU : UInt32 := 'u'.toNat.toUInt32

structure Win where
  id : Nat
  title : String
  x : Float
  y : Float
  w : Float
  h : Float
  deriving Inhabited

-- Where the pointer grabbed a window's title, from its corner.
structure Drag where
  id : Nat
  dx : Float
  dy : Float

structure World where
  windows : List Win      -- back to front
  focus : Nat             -- 0: none
  drag : Option Drag
  nextId : Nat
  mouseX : Float
  mouseY : Float

def Win.contains (w : Win) (x y : Float) : Bool :=
  w.x ≤ x && x < w.x + w.w && w.y ≤ y && y < w.y + w.h

def Win.onTitle (w : Win) (x y : Float) : Bool :=
  w.contains x y && y < w.y + titleH

def Win.onClose (w : Win) (x y : Float) : Bool :=
  w.onTitle x y && x ≥ w.x + w.w - 26

def Win.moveTo (w : Win) (x y : Float) : Win := { w with x := x, y := y }

def World.hit (world : World) (x y : Float) : Option Win :=
  world.windows.reverse.find? (·.contains x y)

def World.raise (world : World) (w : Win) : List Win :=
  world.windows.filter (·.id != w.id) ++ [w]

def World.newWindow (world : World) : World :=
  let n := world.nextId
  let w : Win := { id := n, title := s!"Window {n}",
                   x := world.mouseX, y := world.mouseY, w := 320, h := 200 }
  { world with windows := world.windows ++ [w], focus := n,
               nextId := n + 1 }

def World.step (world : World) : Event → World
  | .press x y =>
    match world.hit x y with
    | none => { world with focus := 0 }
    | some w =>
      if w.onClose x y then
        { world with windows := world.windows.filter (·.id != w.id),
                     focus := 0 }
      else
        let world := { world with windows := world.raise w, focus := w.id }
        if w.onTitle x y then
          { world with drag := some ⟨w.id, x - w.x, y - w.y⟩ }
        else world
  | .motion x y =>
    let world := { world with mouseX := x, mouseY := y }
    match world.drag with
    | none => world
    | some d =>
      { world with windows := world.windows.map fun w =>
          if w.id == d.id then w.moveTo (x - d.dx) (y - d.dy) else w }
  | .release _ _ => { world with drag := none }
  | .key k => if k == keyN then world.newWindow else world
  | .quit => world

end LeanMachine
