import LeanMachine.App

/-! # The world: the windows, the pointer, and what an event does to them

Pure: `World.step` makes a new world and changes nothing. Each window
holds an app. The world drags, raises and closes windows, and passes
other events to the focused window's app. -/

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
  app : App
  x : Float
  y : Float
  w : Float
  h : Float
  deriving Inhabited

def Win.title (w : Win) : String := w.app.title

-- The body: the part below the title, where the app draws.
def Win.bodyX (w : Win) : Float := w.x + 3
def Win.bodyY (w : Win) : Float := w.y + titleH
def Win.bodyW (w : Win) : Float := w.w - 6
def Win.bodyH (w : Win) : Float := w.h - titleH - 3

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

def Win.inBody (w : Win) (x y : Float) : Bool :=
  w.bodyX ≤ x && x < w.bodyX + w.bodyW && w.bodyY ≤ y && y < w.bodyY + w.bodyH

def Win.moveTo (w : Win) (x y : Float) : Win := { w with x := x, y := y }

-- The window after its app hears `e`, moved into the app's coordinates.
def Win.hear (w : Win) (e : Event) : Win :=
  let dx := w.bodyX
  let dy := w.bodyY
  let heard : Option AppEvent := match e with
    | .press x y => some (.press (x - dx) (y - dy))
    | .release x y => some (.release (x - dx) (y - dy))
    | .motion x y => some (.motion (x - dx) (y - dy))
    | .key k => some (.key k)
    | .quit => none
  match heard.bind w.app.step with
  | some app => { w with app }
  | none => w

def World.hit (world : World) (x y : Float) : Option Win :=
  world.windows.reverse.find? (·.contains x y)

def World.raise (world : World) (w : Win) : List Win :=
  world.windows.filter (·.id != w.id) ++ [w]

-- The world after the focused window's app hears `e`.
def World.toFocus (world : World) (e : Event) : World :=
  { world with windows := world.windows.map fun w =>
      if w.id == world.focus then w.hear e else w }

-- A new window at the pointer, holding `app`, in front and focused.
def World.launch (world : World) (app : App) : World :=
  let n := world.nextId
  let w : Win := { id := n, app, x := world.mouseX, y := world.mouseY,
                   w := 320, h := 200 }
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
        else if w.inBody x y then world.toFocus (.press x y)
        else world   -- the frame's edge
  | .motion x y =>
    let world := { world with mouseX := x, mouseY := y }
    match world.drag with
    | none => world.toFocus (.motion x y)
    | some d =>
      { world with windows := world.windows.map fun w =>
          if w.id == d.id then w.moveTo (x - d.dx) (y - d.dy) else w }
  | .release x y =>
    if world.drag.isSome then { world with drag := none }
    else world.toFocus (.release x y)
  | .key k => world.toFocus (.key k)
  | .quit => world

end LeanMachine
