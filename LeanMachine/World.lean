import LeanMachine.App

/-! # The world: windows, the pointer, the menu, and what an event does

Pure: `World.step` makes a new world and changes nothing. Each window
holds an app. The world moves, resizes, raises and closes windows, opens
apps from its menu, tells apps their size, passes ticks to every app,
and passes other events, keys and text included, to the focused
window's app. What apps ask for waits in the world's outbox, marked with
the window that asked, until the loop takes it; the outcome of a run
goes back to that window. -/

namespace LeanMachine

def screenW : Float := 1280
def screenH : Float := 800
def barH : Float := 30        -- the bar along the bottom
def titleH : Float := 28
def frame : Float := 3        -- a window's edge, beside and below its body
-- A window can't be made smaller than this by hand: its title keeps room
-- for the close box, and its body for a few lines of the editor.
def minW : Float := 200
def minH : Float := 140
-- How far outside a window its edges can be grabbed: the frame alone is
-- too thin to find.
def reach : Float := 4
-- How near a corner a grab on one edge takes the other edge too.
def corner : Float := 16
-- How far the pointer goes after a press on a title or an edge before
-- the window follows: a click, or the two of a double click, shouldn't
-- move it.
def dragSlop : Float := 4

-- A window's place on the screen: its corner, and its size with the
-- title and frame.
structure Rect where
  x : Float
  y : Float
  w : Float
  h : Float
  deriving BEq, Inhabited, Repr

-- The edges of a window a drag moves. A title moves all four, which
-- moves the window; an edge moves one, and a corner two, which resizes it.
structure Edges where
  left : Bool := false
  top : Bool := false
  right : Bool := false
  bottom : Bool := false
  deriving BEq, Inhabited, Repr

def Edges.all : Edges := ⟨true, true, true, true⟩
def Edges.any (e : Edges) : Bool := e.left || e.top || e.right || e.bottom

-- `v`, or the nearer of `lo` and `hi` if it's outside them (`lo` if they
-- cross).
def between (lo hi v : Float) : Float := max lo (min hi v)

-- `r` with the edges `es` moved by (dx, dy). All four move it. Fewer
-- resize it, no smaller than `minW` by `minH`, and an edge moved stops at
-- the edge of the desktop (or where it was, if it was past it).
def Rect.drag (r : Rect) (es : Edges) (dx dy : Float) : Rect :=
  if es == .all then { r with x := r.x + dx, y := r.y + dy } else
  let right := r.x + r.w
  let bottom := r.y + r.h
  let left := if es.left then between (min 0 r.x) (right - minW) (r.x + dx) else r.x
  let top := if es.top then between (min 0 r.y) (bottom - minH) (r.y + dy) else r.y
  let right := if es.right then between (left + minW) (max screenW right) (right + dx)
    else right
  let bottom := if es.bottom then between (top + minH) (max (screenH - barH) bottom) (bottom + dy)
    else bottom
  ⟨left, top, right - left, bottom - top⟩

-- Where a maximized window goes: all of the screen above the bar.
def desktopRect : Rect := ⟨0, 0, screenW, screenH - barH⟩

inductive Event where
  | quit
  -- The left button; `clicks` is how many in a row it makes: 2 for the
  -- second press of a double click.
  | press (x y : Float) (clicks : Nat := 1)
  | release (x y : Float)
  | motion (x y : Float)
  | menu (x y : Float)        -- the right button: asks for the menu
  | key (k : Key) (mods : Mods)
  | text (s : String)
  | tick (t : TimeOfDay)      -- from the loop, not the host
  | done (win tag : Nat) (outcome : Outcome) (ms : Nat)  -- from the loop: a run ended
  | launch (win : Nat) (app : App)  -- from the loop: a run in window `win` opened `app`
  | wheel (x y dy : Float)    -- dy steps away from the user, with the pointer at (x, y)
  -- From the loop: a reload that window `win` asked for made these apps,
  -- each the new code of the declaration it's named by.
  | reload (win : Nat) (apps : List (Lean.Name × App))

structure Win where
  id : Nat
  app : App
  x : Float
  y : Float
  w : Float
  h : Float
  -- The declaration its app was opened from, from the menu
  -- (`LeanMachine.clock`); a reload of it replaces the app. `none`: made
  -- in a REPL.
  origin : Option Lean.Name := none
  -- Where it goes back to when it's restored: `some` while it's maximized.
  restore : Option Rect := none
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

def Win.rect (w : Win) : Rect := ⟨w.x, w.y, w.w, w.h⟩
def Win.maximized (w : Win) : Bool := w.restore.isSome

-- Where a drag of the title from `x` starts: where the window is, or for
-- a maximized one, its restored size under the pointer, as far along its
-- title as the pointer is along this one.
def Win.dragFrom (w : Win) (x : Float) : Rect :=
  match w.restore with
  | some r => { r with x := x - (x - w.x) / w.w * r.w, y := w.y }
  | none => w.rect

-- A window being dragged: the edges that move, and where the window and
-- the pointer were at the press.
structure Drag where
  id : Nat
  edges : Edges
  start : Rect
  px : Float
  py : Float
  moved : Bool := false   -- past `dragSlop` yet

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
  catalog : List (Lean.Name × App)  -- what the menu opens, by declaration
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

-- The box left of the close box, which maximizes the window or restores it.
def Win.onMax (w : Win) (x y : Float) : Bool :=
  w.onTitle x y && x ≥ w.x + w.w - 46 && x < w.x + w.w - 26

def Win.inBody (w : Win) (x y : Float) : Bool :=
  w.bodyX ≤ x && x < w.bodyX + w.bodyW && w.bodyY ≤ y && y < w.bodyY + w.bodyH

-- The edges a press at (x, y) grabs: within `reach` outside the window,
-- or in its frame (on top, the title's first `frame` pixels). Near a
-- corner, or on the grip, both of the corner's edges. None elsewhere.
def Win.edgesAt (w : Win) (x y : Float) : Edges :=
  let right := w.x + w.w
  let bottom := w.y + w.h
  if !(w.x - reach ≤ x && x < right + reach && w.y - reach ≤ y && y < bottom + reach) then {}
  else if x ≥ right - frame - gripSize && y ≥ bottom - frame - gripSize then
    { right := true, bottom := true }
  else
    let l := x < w.x + frame
    let r := x ≥ right - frame
    let t := y < w.y + frame
    let b := y ≥ bottom - frame
    { left := l || (t || b) && x < w.x + corner,
      right := r || (t || b) && x ≥ right - corner,
      top := t || (l || r) && y < w.y + corner,
      bottom := b || (l || r) && y ≥ bottom - corner }

-- `e` as the window's app hears it, moved into the app's coordinates.
def Win.toApp (w : Win) : Event → Option AppEvent
  | .press x y _ => some (.press (x - w.bodyX) (y - w.bodyY))
  | .release x y => some (.release (x - w.bodyX) (y - w.bodyY))
  | .motion x y => some (.motion (x - w.bodyX) (y - w.bodyY))
  | .key k m => some (.key k m)
  | .text s => some (.text s)
  | .tick t => some (.tick t)
  | .done _ tag o ms => some (.done tag o ms)
  | .wheel x y dy => some (.wheel (x - w.bodyX) (y - w.bodyY) dy)
  | .menu .. | .launch .. | .reload .. | .quit => none

-- The window after its app hears `e`, in the app's own terms already,
-- and what the app asked for.
def Win.heed (w : Win) (e : AppEvent) : Win × List Asked :=
  match w.app.step e with
  | some (app, asks) => ({ w with app }, asks.map (⟨w.id, ·⟩))
  | none => (w, [])

-- The window after its app hears `e`, and what the app asked for.
def Win.hear (w : Win) (e : Event) : Win × List Asked :=
  match w.toApp e with
  | some e => w.heed e
  | none => (w, [])

-- The window at `r`. If its body's size changed, its app hears the new
-- size; a move alone tells it nothing.
def Win.place (w : Win) (r : Rect) : Win × List Asked :=
  let moved := { w with x := r.x, y := r.y, w := r.w, h := r.h }
  if moved.bodyW == w.bodyW && moved.bodyH == w.bodyH then (moved, [])
  else moved.heed (.resize moved.bodyW moved.bodyH)

def World.hit (world : World) (x y : Float) : Option Win :=
  world.windows.reverse.find? (·.contains x y)

-- What a press at (x, y) lands on: the frontmost window it's in or near
-- enough to grab an edge of, and the edges it grabs (none: inside, away
-- from the edges).
def World.grabAt (world : World) (x y : Float) : Option (Win × Edges) :=
  world.windows.reverse.findSome? fun w =>
    let es := w.edgesAt x y
    if es.any || w.contains x y then some (w, es) else none

def World.raise (world : World) (w : Win) : List Win :=
  world.windows.filter (·.id != w.id) ++ [w]

-- The world after `f` changes the windows `pick` chooses, with what
-- their apps asked for in the outbox.
def World.each (world : World) (pick : Win → Bool) (f : Win → Win × List Asked) : World :=
  let (windows, asked) := (world.windows.map fun w =>
    if pick w then f w else (w, [])).unzip
  { world with windows, outbox := asked.flatten.reverse ++ world.outbox }

-- The world after the apps of the windows `pick` chooses hear `e`.
def World.tell (world : World) (pick : Win → Bool) (e : Event) : World :=
  world.each pick (·.hear e)

-- Window `id` at `r`, its app told its new size. A drag places a window
-- at every motion; maximizing, tiling and cascading would place them too.
def World.place (world : World) (id : Nat) (r : Rect) : World :=
  world.each (·.id == id) (·.place r)

-- Window `id` maximized, to fill the desktop, or if it is, restored to
-- where it was; its app hears its new size.
def World.toggleMax (world : World) (id : Nat) : World :=
  world.each (·.id == id) fun w =>
    match w.restore with
    | some r => { w with restore := none }.place r
    | none => { w with restore := some w.rect }.place desktopRect

def World.toFocus (world : World) (e : Event) : World :=
  world.tell (·.id == world.focus) e

def World.toAll (world : World) (e : Event) : World :=
  world.tell (fun _ => true) e

-- Window `n` holding `app`, as it starts, at (x, y) or as near as keeps
-- it on the screen, its body `size` (none: the size the app asks for).
-- The app hears its size first, then the time, so a clock is right from
-- its first frame; what it asks for then goes in the outbox.
def World.fresh (world : World) (n : Nat) (app : App) (x y : Float)
    (origin : Option Lean.Name) (size : Option (Float × Float) := none) : Win × World :=
  let (bw, bh) := size.getD app.size
  let w := bw + 2 * frame
  let h := bh + titleH + frame
  let win : Win := { id := n, app, w, h, origin,
                     x := max 0 (min x (screenW - w)),
                     y := max 0 (min y (screenH - barH - h)) }
  let (win, sized) := win.heed (.resize win.bodyW win.bodyH)
  let (win, timed) := win.heed (.tick world.time)
  (win, { world with outbox := (sized ++ timed).reverse ++ world.outbox })

-- A new window holding `app`, with its corner at (x, y) or as near as
-- keeps it on the screen, in front and focused.
def World.launch (world : World) (app : App) (x y : Float)
    (origin : Option Lean.Name := none) : World :=
  let n := world.nextId
  let (win, world) := world.fresh n app x y origin
  { world with windows := world.windows ++ [win], focus := n, nextId := n + 1 }

-- `app`, the new code of the declaration `name`, made by a reload that
-- window `win` asked for. It takes the old app's place in the menu (or
-- goes at the end of it), and in every window opened from it, where the
-- window is and at its size, as it starts: its state was in the old
-- app's closures, which the new code can't read. Not in window `win`:
-- an editor that reloads its own file keeps it. When no other window has
-- it, it opens in a new one beside `win`.
def World.reload (world : World) (win : Nat) (name : Lean.Name) (app : App) : World :=
  let catalog := if world.catalog.any (·.1 == name)
    then world.catalog.map fun (n, a) => (n, if n == name then app else a)
    else world.catalog ++ [(name, app)]
  let world := { world with catalog }
  if world.windows.any fun w => w.origin == some name && w.id != win then
    world.windows.foldl (init := { world with windows := [] }) fun world w =>
      if w.origin == some name && w.id != win then
        let (nw, world) := world.fresh w.id app w.x w.y (some name) (some (w.bodyW, w.bodyH))
        { world with windows := world.windows ++ [{ nw with restore := w.restore }] }
      else { world with windows := world.windows ++ [w] }
  else match world.windows.find? (·.id == win) with
    | some w => world.launch app (w.x + w.w + 12) w.y (some name)
    | none => world.launch app world.mouseX world.mouseY (some name)

-- The menu, open at (x, y) or as near as keeps it on the screen.
def World.openMenu (world : World) (x y : Float) : World :=
  { world with menu := some ⟨max 0 (min x (screenW - menuW)),
                             max 0 (min y (screenH - barH - world.menuH))⟩ }

-- What an event does to the windows, with no menu in the way.
def World.stepWindows (world : World) : Event → World
  | .press x y clicks =>
    match world.grabAt x y with
    | none => { world with focus := 0 }
    | some (w, es) =>
      if !es.any && w.onClose x y then
        { world with windows := world.windows.filter (·.id != w.id),
                     focus := 0 }
      else
        let world := { world with windows := world.raise w, focus := w.id }
        let grab (es : Edges) (start : Rect) : World :=
          { world with drag := some { id := w.id, edges := es, start, px := x, py := y } }
        if es.any then grab es w.rect          -- an edge or a corner: resizes it
        else if w.onMax x y then world.toggleMax w.id
        else if w.onTitle x y then
          if clicks % 2 == 0 then world.toggleMax w.id   -- a double click
          else grab .all (w.dragFrom x)                  -- moves it
        else if w.inBody x y then world.toFocus (.press x y clicks)
        else world
  -- A drag that has gone past `dragSlop` moves the window's edges with
  -- the pointer; a maximized window is maximized no more.
  | .motion x y =>
    let world := { world with mouseX := x, mouseY := y }
    match world.drag with
    | none => world.toFocus (.motion x y)
    | some d =>
      if !d.moved && (x - d.px).abs < dragSlop && (y - d.py).abs < dragSlop then world
      else
        let world := { world with drag := some { d with moved := true } }
        world.each (·.id == d.id) fun w =>
          { w with restore := none }.place (d.start.drag d.edges (x - d.px) (y - d.py))
  | .release x y =>
    if world.drag.isSome then { world with drag := none }
    else world.toFocus (.release x y)
  | .menu x y => world.openMenu x y
  | .key k m =>
    if desktopKey 'n' k m then world.openMenu world.mouseX world.mouseY
    else if desktopKey 'm' k m then world.toggleMax world.focus
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
  | .reload win apps => apps.foldl (fun world (name, app) => world.reload win name app) world
  | .quit => world

-- With the menu open, a press on an item opens its app where the menu
-- was; a press anywhere else only closes the menu, and so does Esc. Other
-- keys and text still go to the focused app.
def World.step (world : World) (e : Event) : World :=
  match world.menu, e with
  | some m, .press x y _ =>
    let world := { world with menu := none }
    match (world.itemAt? m x y).bind fun i => world.catalog[i]? with
    | some (name, app) => world.launch app m.x m.y (some name)
    | none => world
  | some _, .key .escape _ => { world with menu := none }
  | _, _ => world.stepWindows e

-- What the apps asked for, oldest first, and the world with its outbox
-- emptied.
def World.takeAsked (world : World) : World × List Asked :=
  ({ world with outbox := [] }, world.outbox.reverse)

-- Whether `e` starts a step undo can return to. A press does, unless it
-- only closes the menu, and so does a reload, so undo brings the old apps
-- back, and Ctrl+Shift+M with a window focused; nothing else does.
def World.commits (world : World) : Event → Bool
  | .press x y _ =>
    match world.menu with
    | some m => (world.itemAt? m x y).isSome
    | none => true
  | .reload .. => true
  | .key k m => desktopKey 'm' k m && world.focus != 0
  | _ => false

end LeanMachine
