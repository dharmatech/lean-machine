import LeanMachine.App

/-! # Windows, and the screen they're on

The `Screen`, whose size the world holds, a window's parts (`titleH`,
`frame`), the `Event`s the desktop hears, and `Win`, a window holding
an app: where
it is, what a press on it finds (its title's boxes, its body, the
`Edges` it grabs, which a drag moves with `Rect.drag`), and what its
app hears, moved into the app's coordinates (`Win.hear`). `Win.place`
puts it at a `Rect`, and its app hears its new size. -/

namespace LeanMachine

def barH : Float := 30        -- the taskbar, along the bottom
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
-- How much of its title a moved window keeps above the bar, which is in
-- front of it, so that a press can still find the title.
def titleKept : Float := 20

-- The screen: the size of the host's window, which the world holds
-- (`World.screen`). It starts at 1280 by 800.
structure Screen where
  w : Float := 1280
  h : Float := 800
  deriving BEq, Inhabited, Repr

-- The top of the taskbar, along the bottom of the screen.
def Screen.barY (s : Screen) : Float := s.h - barH

-- Where a maximized window goes: all of the screen above the bar.
def Screen.desktop (s : Screen) : Rect := ⟨0, 0, s.w, s.barY⟩

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

-- `r` with the edges `es` moved by (dx, dy), on `screen`. All four move
-- it, anywhere but down past `titleKept` above the bar. Fewer resize it,
-- no smaller than `minW` by `minH`, and an edge moved stops at the edge
-- of the desktop (or where it was, if it was past it).
def Rect.drag (r : Rect) (screen : Screen) (es : Edges) (dx dy : Float) : Rect :=
  if es == .all then
    { r with x := r.x + dx, y := min (r.y + dy) (max r.y (screen.barY - titleKept)) }
  else
  let right := r.x + r.w
  let bottom := r.y + r.h
  let left := if es.left then between (min 0 r.x) (right - minW) (r.x + dx) else r.x
  let top := if es.top then between (min 0 r.y) (bottom - minH) (r.y + dy) else r.y
  let right := if es.right then between (left + minW) (max screen.w right) (right + dx)
    else right
  let bottom := if es.bottom then between (top + minH) (max screen.barY bottom) (bottom + dy)
    else bottom
  ⟨left, top, right - left, bottom - top⟩

-- `r` moved from screen `old` to screen `new`: with as much of it on the
-- screen as there was, if `new` has room. A screen that grows moves
-- nothing. One that shrinks pushes it left by its right edge and up by
-- the bar, so that a window hanging off the edge hangs off it as far,
-- but no further than the screen's left and top edges (or where it was,
-- if it was past them).
def Rect.keepOn (r : Rect) (old new : Screen) : Rect :=
  -- How much of it was left of the right edge, and above the bar.
  let seenW := min r.w (old.w - r.x)
  let seenH := min r.h (old.barY - r.y)
  { r with x := max (min 0 r.x) (min r.x (new.w - seenW)),
           y := max (min 0 r.y) (min r.y (new.barY - seenH)) }

#guard (Rect.keepOn ⟨500, 340, 420, 260⟩ {} ⟨900, 600⟩) == ⟨480, 310, 420, 260⟩
#guard (Rect.keepOn ⟨80, 70, 566, 331⟩ {} ⟨900, 600⟩) == ⟨80, 70, 566, 331⟩
#guard (Rect.keepOn ⟨1000, 340, 420, 260⟩ {} ⟨900, 600⟩) == ⟨620, 310, 420, 260⟩  -- 140 off, still
#guard (Rect.keepOn ⟨80, 70, 566, 331⟩ {} ⟨400, 300⟩) == ⟨0, 0, 566, 331⟩
#guard (Rect.keepOn ⟨500, 340, 420, 260⟩ {} ⟨1600, 1000⟩) == ⟨500, 340, 420, 260⟩

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
  | frame (ms : Nat)          -- from the loop: 60 a second while an app animates
  | done (win tag : Nat) (outcome : Outcome) (ms : Nat)  -- from the loop: a run ended
  | launch (win : Nat) (app : App)  -- from the loop: a run in window `win` opened `app`
  | wheel (x y dy : Float)    -- dy steps away from the user, with the pointer at (x, y)
  -- From the loop: a reload that window `win` asked for made these apps,
  -- each the new code of the declaration it's named by.
  | reload (win : Nat) (apps : List (Lean.Name × App))
  | screen (w h : Float)      -- from the host: its window is now w by h

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
  -- Only on the taskbar: not drawn, and no press finds it. Its place and
  -- `restore` stay as they were, so it comes back as it was. Its app
  -- still hears ticks and how its runs ended.
  minimized : Bool := false
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

-- Its place on the screen: its corner, and its size with the title and
-- frame.
def Win.rect (w : Win) : Rect := ⟨w.x, w.y, w.w, w.h⟩
def Win.maximized (w : Win) : Bool := w.restore.isSome

-- Where a drag of the title from `x` starts: where the window is, or for
-- a maximized one, its restored size under the pointer, as far along its
-- title as the pointer is along this one.
def Win.dragFrom (w : Win) (x : Float) : Rect :=
  match w.restore with
  | some r => { r with x := x - (x - w.x) / w.w * r.w, y := w.y }
  | none => w.rect


def Win.contains (w : Win) (x y : Float) : Bool :=
  w.x ≤ x && x < w.x + w.w && w.y ≤ y && y < w.y + w.h

def Win.onTitle (w : Win) (x y : Float) : Bool :=
  w.contains x y && y < w.y + titleH

def Win.onClose (w : Win) (x y : Float) : Bool :=
  w.onTitle x y && x ≥ w.x + w.w - 26

-- The box left of the close box, which maximizes the window or restores it.
def Win.onMax (w : Win) (x y : Float) : Bool :=
  w.onTitle x y && x ≥ w.x + w.w - 46 && x < w.x + w.w - 26

-- The box left of that, which minimizes the window.
def Win.onMin (w : Win) (x y : Float) : Bool :=
  w.onTitle x y && x ≥ w.x + w.w - 66 && x < w.x + w.w - 46

-- Any of the three boxes.
def Win.onBoxes (w : Win) (x y : Float) : Bool :=
  w.onTitle x y && x ≥ w.x + w.w - 66

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
  | .frame ms => some (.frame ms)
  | .done _ tag o ms => some (.done tag o ms)
  | .wheel x y dy => some (.wheel (x - w.bodyX) (y - w.bodyY) dy)
  | .menu .. | .launch .. | .reload .. | .screen .. | .quit => none

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

end LeanMachine
