import LeanMachine.Taskbar

/-! # The world: windows, the pointer, the menu, and what an event does

Pure: `World.step` makes a new world and changes nothing. Each window
(Win.lean) holds an app. The world moves, resizes, raises, minimizes
and closes windows, lays out the taskbar along the bottom
(Taskbar.lean), opens apps from its menu, tells apps their size, passes
ticks to every app, and passes other events, keys and text included, to
the focused window's app. What apps ask for waits in the world's outbox,
marked with the window that asked, until the loop takes it; the outcome
of a run goes back to that window. -/

namespace LeanMachine

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
  screen : Screen := {}      -- the host's window

def World.menuH (world : World) : Float :=
  menuHeadH + itemH * world.catalog.length.toFloat + 6

-- The number of the item of `m` at (x, y), if there is one.
def World.itemAt? (world : World) (m : Menu) (x y : Float) : Option Nat :=
  if m.x ≤ x && x < m.x + menuW && m.itemY 0 ≤ y then
    let i := ((y - m.itemY 0) / itemH).floor.toUInt64.toNat
    if i < world.catalog.length then some i else none
  else none

-- The windows that aren't minimized, back to front: those drawn, and
-- those tiling and cascading would place.
def World.visible (world : World) : List Win :=
  world.windows.filter (!·.minimized)

-- Whether an app in a window that isn't minimized wants frames: the
-- loop draws 60 a second while one does.
def World.animating (world : World) : Bool :=
  world.visible.any (·.app.animating)

-- The frontmost window at (x, y), above the bar.
def World.hit (world : World) (x y : Float) : Option Win :=
  if world.screen.inBar y then none else world.visible.reverse.find? (·.contains x y)

-- What a press at (x, y) above the bar lands on: the frontmost window
-- it's in or near enough to grab an edge of, and the edges it grabs
-- (none: inside, away from the edges).
def World.grabAt (world : World) (x y : Float) : Option (Win × Edges) :=
  if world.screen.inBar y then none else
  world.visible.reverse.findSome? fun w =>
    let es := w.edgesAt x y
    if es.any || w.contains x y then some (w, es) else none

-- The world's taskbar: a button for each of its windows.
def World.taskbar (world : World) : Taskbar :=
  .of world.screen world.windows

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
    | none => { w with restore := some w.rect }.place world.screen.desktop

-- The frontmost window that isn't minimized, or 0 if there's none.
def World.frontmost (world : World) : Nat :=
  (world.visible.getLast?.map (·.id)).getD 0

-- Window `id` minimized, and if it had the focus, the frontmost window
-- left has it.
def World.minimize (world : World) (id : Nat) : World :=
  if !world.windows.any (·.id == id) then world else
  let world := { world with windows := world.windows.map fun w =>
    if w.id == id then { w with minimized := true } else w }
  if world.focus == id then { world with focus := world.frontmost } else world

-- Window `id` in front and focused, and if it was minimized, back where
-- it was.
def World.focusOn (world : World) (id : Nat) : World :=
  match world.windows.find? (·.id == id) with
  | some w => { world with windows := world.raise { w with minimized := false }, focus := id }
  | none => world

-- What a press on window `w`'s button on the taskbar does: minimizes it
-- if it's focused, or brings it to the front and focuses it.
def World.pressButton (world : World) (w : Win) : World :=
  if w.id == world.focus then world.minimize w.id else world.focusOn w.id

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
                     x := max 0 (min x (world.screen.w - w)),
                     y := max 0 (min y (world.screen.barY - h)) }
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
        { world with windows := world.windows ++
            [{ nw with restore := w.restore, minimized := w.minimized }] }
      else { world with windows := world.windows ++ [w] }
  else match world.windows.find? (·.id == win) with
    | some w => world.launch app (w.x + w.w + 12) w.y (some name)
    | none => world.launch app world.mouseX world.mouseY (some name)

-- The menu, open at (x, y) or as near as keeps it on the screen.
def World.openMenu (world : World) (x y : Float) : World :=
  { world with menu := some ⟨max 0 (min x (world.screen.w - menuW)),
                             max 0 (min y (world.screen.barY - world.menuH))⟩ }

-- The world on screen `s`, the host's window resized. Each window keeps
-- as much of itself on the screen as it can (`Rect.keepOn`), and so does
-- the place a maximized one goes back to; a maximized window fills the
-- new desktop. An app hears its size if it changed. An open menu stays
-- on the screen. The taskbar is laid out from the screen each time.
def World.onScreen (world : World) (s : Screen) : World :=
  if s == world.screen then world else
  let old := world.screen
  let world := { world with screen := s }
  let world := world.each (fun _ => true) fun w =>
    match w.restore with
    | some r => { w with restore := some (r.keepOn old s) }.place s.desktop
    | none => w.place (w.rect.keepOn old s)
  match world.menu with
  | some m => world.openMenu m.x m.y
  | none => world

-- What an event does to the windows, with no menu in the way.
def World.stepWindows (world : World) : Event → World
  | .press x y clicks =>
    if world.screen.inBar y then
      match world.taskbar.buttonAt x y with
      | some w => world.pressButton w
      | none => world
    else
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
        else if w.onMin x y then world.minimize w.id
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
          { w with restore := none }.place (d.start.drag world.screen d.edges (x - d.px) (y - d.py))
  | .release x y =>
    if world.drag.isSome then { world with drag := none }
    else world.toFocus (.release x y)
  | .menu x y => world.openMenu x y
  | .key k m =>
    if desktopKey 'n' k m then world.openMenu world.mouseX world.mouseY
    else if desktopKey 'm' k m then world.toggleMax world.focus
    else if desktopKey 'h' k m then world.minimize world.focus
    else world.toFocus (.key k m)
  | .text s => world.toFocus (.text s)
  | .paste s => world.toFocus (.paste s)
  -- The wheel goes to the window under the pointer, focused or not.
  | .wheel x y dy =>
    match world.hit x y with
    | some w => world.tell (·.id == w.id) (.wheel x y dy)
    | none => world
  | .tick t => { world.toAll (.tick t) with time := t }
  | .frame ms => world.tell (fun w => !w.minimized && w.app.animating) (.frame ms)
  | .done win tag o ms => world.tell (·.id == win) (.done win tag o ms)
  | .launch win app =>
    match world.windows.find? (·.id == win) with
    | some w => world.launch app (w.x + 40) (w.y + 40)
    | none => world.launch app world.mouseX world.mouseY
  | .reload win apps => apps.foldl (fun world (name, app) => world.reload win name app) world
  | .screen w h => world.onScreen ⟨w, h⟩
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
-- only closes the menu or misses the taskbar's buttons, and so does a
-- reload, so undo brings the old apps back, and with a window focused,
-- Ctrl+Shift+M, Ctrl+Shift+H and a paste, so undo takes the paste back
-- alone; nothing else does.
def World.commits (world : World) : Event → Bool
  | .press x y _ =>
    match world.menu with
    | some m => (world.itemAt? m x y).isSome
    | none => !world.screen.inBar y || (world.taskbar.buttonAt x y).isSome
  | .reload .. => true
  | .key k m => (desktopKey 'm' k m || desktopKey 'h' k m) && world.focus != 0
  | .paste _ => world.focus != 0
  | _ => false

end LeanMachine
