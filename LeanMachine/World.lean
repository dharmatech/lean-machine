import LeanMachine.App

/-! # The world: windows, the pointer, the menu, and what an event does

Pure: `World.step` makes a new world and changes nothing. Each window
holds an app. The world drags, raises and closes windows, opens apps from
its menu, passes ticks to every app, and passes other events, keys and
text included, to the focused window's app. What apps ask for waits in
the world's outbox, marked with the window that asked, until the loop
takes it; the outcome of a run goes back to that window. -/

namespace LeanMachine

def screenW : Float := 1280
def screenH : Float := 800
def barH : Float := 30        -- the bar along the bottom
def titleH : Float := 28
def frame : Float := 3        -- a window's edge, beside and below its body

inductive Event where
  | quit
  | press (x y : Float)       -- the left button
  | release (x y : Float)
  | motion (x y : Float)
  | menu (x y : Float)        -- the right button: asks for the menu
  | key (k : Key) (mods : Mods)
  | text (s : String)
  | tick (t : TimeOfDay)      -- from the loop, not the host
  | done (win tag : Nat) (outcome : Outcome) (ms : Nat)  -- from the loop: a run ended
  | launch (win : Nat) (app : App)  -- from the loop: a run in window `win` opened `app`
  | wheel (x y dy : Float)    -- dy steps away from the user, with the pointer at (x, y)

structure Win where
  id : Nat
  app : App
  x : Float
  y : Float
  w : Float
  h : Float
  deriving Inhabited

def Win.title (w : Win) : String := w.app.title

-- A request, and the window whose app made it.
structure Asked where
  win : Nat
  request : Request

-- The body: the part below the title, where the app draws.
def Win.bodyX (w : Win) : Float := w.x + frame
def Win.bodyY (w : Win) : Float := w.y + titleH
def Win.bodyW (w : Win) : Float := w.w - 2 * frame
def Win.bodyH (w : Win) : Float := w.h - titleH - frame

-- Where the pointer grabbed a window's title, from its corner.
structure Drag where
  id : Nat
  dx : Float
  dy : Float

-- The menu that opens apps: where its corner is. Its items are the
-- world's catalog, one per app.
structure Menu where
  x : Float
  y : Float

def menuW : Float := 180
def menuHeadH : Float := 28   -- the line that says what the menu does
def itemH : Float := 26

-- The top of item `i`.
def Menu.itemY (m : Menu) (i : Nat) : Float :=
  m.y + menuHeadH + itemH * i.toFloat

structure World where
  windows : List Win      -- back to front
  focus : Nat             -- 0: none
  drag : Option Drag
  menu : Option Menu      -- none: closed
  catalog : List App      -- what the menu opens
  time : TimeOfDay        -- the last tick's; a new app hears it as it opens
  nextId : Nat
  mouseX : Float
  mouseY : Float
  outbox : List Asked := []  -- what apps asked for, newest first

def World.menuH (world : World) : Float :=
  menuHeadH + itemH * world.catalog.length.toFloat + 6

-- The number of the item of `m` at (x, y), if there is one.
def World.itemAt? (world : World) (m : Menu) (x y : Float) : Option Nat :=
  if m.x ≤ x && x < m.x + menuW && m.itemY 0 ≤ y then
    let i := ((y - m.itemY 0) / itemH).floor.toUInt64.toNat
    if i < world.catalog.length then some i else none
  else none

def Win.contains (w : Win) (x y : Float) : Bool :=
  w.x ≤ x && x < w.x + w.w && w.y ≤ y && y < w.y + w.h

def Win.onTitle (w : Win) (x y : Float) : Bool :=
  w.contains x y && y < w.y + titleH

def Win.onClose (w : Win) (x y : Float) : Bool :=
  w.onTitle x y && x ≥ w.x + w.w - 26

def Win.inBody (w : Win) (x y : Float) : Bool :=
  w.bodyX ≤ x && x < w.bodyX + w.bodyW && w.bodyY ≤ y && y < w.bodyY + w.bodyH

def Win.moveTo (w : Win) (x y : Float) : Win := { w with x := x, y := y }

-- `e` as the window's app hears it, moved into the app's coordinates.
def Win.toApp (w : Win) : Event → Option AppEvent
  | .press x y => some (.press (x - w.bodyX) (y - w.bodyY))
  | .release x y => some (.release (x - w.bodyX) (y - w.bodyY))
  | .motion x y => some (.motion (x - w.bodyX) (y - w.bodyY))
  | .key k m => some (.key k m)
  | .text s => some (.text s)
  | .tick t => some (.tick t)
  | .done _ tag o ms => some (.done tag o ms)
  | .wheel x y dy => some (.wheel (x - w.bodyX) (y - w.bodyY) dy)
  | .menu .. | .launch .. | .quit => none

-- The window after its app hears `e`, and what the app asked for.
def Win.hear (w : Win) (e : Event) : Win × List Asked :=
  match (w.toApp e).bind w.app.step with
  | some (app, asks) => ({ w with app }, asks.map (⟨w.id, ·⟩))
  | none => (w, [])

def World.hit (world : World) (x y : Float) : Option Win :=
  world.windows.reverse.find? (·.contains x y)

def World.raise (world : World) (w : Win) : List Win :=
  world.windows.filter (·.id != w.id) ++ [w]

-- The world after the apps of the windows `pick` chooses hear `e`, with
-- what they asked for in the outbox.
def World.tell (world : World) (pick : Win → Bool) (e : Event) : World :=
  let (windows, asked) := (world.windows.map fun w =>
    if pick w then w.hear e else (w, [])).unzip
  { world with windows, outbox := asked.flatten.reverse ++ world.outbox }

def World.toFocus (world : World) (e : Event) : World :=
  world.tell (·.id == world.focus) e

def World.toAll (world : World) (e : Event) : World :=
  world.tell (fun _ => true) e

-- A new window holding `app`, with its corner at (x, y) or as near as
-- keeps it on the screen, in front and focused. The app hears the time
-- first, so a clock is right from its first frame.
def World.launch (world : World) (app : App) (x y : Float) : World :=
  let n := world.nextId
  let (app, asks) := (app.step (.tick world.time)).getD (app, [])
  let w := app.size.1 + 2 * frame
  let h := app.size.2 + titleH + frame
  let win : Win := { id := n, app, w, h,
                     x := max 0 (min x (screenW - w)),
                     y := max 0 (min y (screenH - barH - h)) }
  { world with windows := world.windows ++ [win], focus := n,
               nextId := n + 1,
               outbox := (asks.map (⟨n, ·⟩)).reverse ++ world.outbox }

-- The menu, open at (x, y) or as near as keeps it on the screen.
def World.openMenu (world : World) (x y : Float) : World :=
  { world with menu := some ⟨max 0 (min x (screenW - menuW)),
                             max 0 (min y (screenH - barH - world.menuH))⟩ }

-- What an event does to the windows, with no menu in the way.
def World.stepWindows (world : World) : Event → World
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
  | .menu x y => world.openMenu x y
  | .key k m =>
    if desktopKey 'n' k m then world.openMenu world.mouseX world.mouseY
    else world.toFocus (.key k m)
  | .text s => world.toFocus (.text s)
  -- The wheel goes to the window under the pointer, focused or not.
  | .wheel x y dy =>
    match world.hit x y with
    | some w => world.tell (·.id == w.id) (.wheel x y dy)
    | none => world
  | .tick t => { world.toAll (.tick t) with time := t }
  | .done win tag o ms => world.tell (·.id == win) (.done win tag o ms)
  | .launch win app =>
    match world.windows.find? (·.id == win) with
    | some w => world.launch app (w.x + 40) (w.y + 40)
    | none => world.launch app world.mouseX world.mouseY
  | .quit => world

-- With the menu open, a press on an item opens its app where the menu
-- was; a press anywhere else only closes the menu, and so does Esc. Other
-- keys and text still go to the focused app.
def World.step (world : World) (e : Event) : World :=
  match world.menu, e with
  | some m, .press x y =>
    let world := { world with menu := none }
    match (world.itemAt? m x y).bind fun i => world.catalog[i]? with
    | some app => world.launch app m.x m.y
    | none => world
  | some _, .key .escape _ => { world with menu := none }
  | _, _ => world.stepWindows e

-- What the apps asked for, oldest first, and the world with its outbox
-- emptied.
def World.takeAsked (world : World) : World × List Asked :=
  ({ world with outbox := [] }, world.outbox.reverse)

-- Whether `e` starts a step undo can return to. A press does, unless it
-- only closes the menu; nothing else does.
def World.commits (world : World) : Event → Bool
  | .press x y =>
    match world.menu with
    | some m => (world.itemAt? m x y).isSome
    | none => true
  | _ => false

end LeanMachine
