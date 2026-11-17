-- A desktop as a value. `World.step` and `World.view` are pure; the loop at
-- the bottom is the only code that does I/O, and `render` the only code
-- that draws.

/-! ## The host: a canvas and one window (shim.c) -/

opaque CanvasPointed : NonemptyType
def Canvas := CanvasPointed.type
instance : Nonempty Canvas := CanvasPointed.property

@[extern "sv_canvas_new"] opaque Canvas.new (w h : UInt32) : IO Canvas
@[extern "sv_fill_rect"] opaque Canvas.fillRect (c : @& Canvas)
  (x y w h radius : Float) (rgb : UInt32) : IO Unit
@[extern "sv_text"] opaque Canvas.text (c : @& Canvas)
  (x y size : Float) (rgb : UInt32) (s : @& String) : IO Unit
@[extern "sv_save_png"] opaque Canvas.savePng (c : @& Canvas)
  (path : @& String) : IO Unit

@[extern "sv_host_open"] opaque Host.open (title : @& String)
  (w h : UInt32) : IO Unit
@[extern "sv_host_present"] opaque Host.present (c : @& Canvas) : IO Unit
@[extern "sv_host_event"] opaque Host.event (timeoutMs : UInt32) : IO FloatArray

/-! ## Pictures and events: plain data -/

inductive Picture where
  | rect (x y w h radius : Float) (rgb : UInt32)
  | text (x y size : Float) (rgb : UInt32) (s : String)
  | group (ps : List Picture)

inductive Event where
  | quit
  | press (x y : Float)
  | release (x y : Float)
  | motion (x y : Float)
  | key (code : UInt32)

def Event.decode (a : FloatArray) : Option Event :=
  let x := a.get! 1
  let y := a.get! 2
  match (a.get! 0).toUInt32 with
  | 1 => some .quit
  | 2 => if a.get! 3 == 1 then some (.press x y) else none   -- left button
  | 3 => some (.release x y)
  | 4 => some (.motion x y)
  | 5 => some (.key x.toUInt32)
  | _ => none

def keyEscape : UInt32 := 27
def keyN : UInt32 := 'n'.toNat.toUInt32
def keyU : UInt32 := 'u'.toNat.toUInt32

/-! ## The world -/

def screenW : Float := 1280
def screenH : Float := 800
def titleH : Float := 28

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

/-! ## The desktop: the world now, and every world before it -/

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

/-! ## The view -/

def Win.view (w : Win) (focused : Bool) : Picture :=
  .group [
    .rect w.x w.y w.w w.h 8 (if focused then 0xbb9af7 else 0x565f89),
    .rect (w.x + 3) (w.y + titleH) (w.w - 6) (w.h - titleH - 3) 6 0x1a1b26,
    .text (w.x + 12) (w.y + 19) 14 0x1a1b26 w.title,
    .rect (w.x + w.w - 22) (w.y + 7) 14 14 3
      (if focused then 0xf7768e else 0x414868),
    .text (w.x + 14) (w.y + titleH + 24) 13 0x9aa5ce
      s!"id {w.id}   x {w.x.toUInt32}   y {w.y.toUInt32}" ]

def Desktop.view (d : Desktop) : Picture :=
  let world := d.now
  .group ([.rect 0 0 screenW screenH 0 0x24283b] ++
    world.windows.map (fun w => w.view (w.id == world.focus)) ++
    [.rect 0 (screenH - 30) screenW 30 0 0x16161e,
     .text 14 (screenH - 10) 13 0x7aa2f7
       s!"{d.past.length} earlier worlds   ·   drag a title   ·   \
          click the box to close   ·   N new window   ·   U undo   ·   \
          Esc quits"])

partial def render (c : Canvas) : Picture → IO Unit
  | .rect x y w h r rgb => c.fillRect x y w h r rgb
  | .text x y size rgb s => c.text x y size rgb s
  | .group ps => ps.forM (render c)

def start : Desktop :=
  let titles := ["REPL", "Clock", "Inspector", "Notes"]
  { past := [],
    now := { focus := 4, drag := none, nextId := 5, mouseX := 600,
             mouseY := 400,
             windows := titles.zipIdx.map fun (t, i) =>
               { id := i + 1, title := t, x := 80 + 140 * i.toFloat,
                 y := 70 + 90 * i.toFloat, w := 420, h := 260 } } }

/-! ## The loop: the only I/O -/

-- Applies every waiting event, then draws once. `frames` stops it early
-- (for tests); the window's close button or Esc stops it any time.
partial def run (c : Canvas) (d : Desktop) (frames : Option Nat) : IO Unit := do
  if frames == some 0 then return
  let mut d := d
  let mut quit := false
  let mut raw ← Host.event 100
  while raw.get! 0 != 0 do
    match Event.decode raw with
    | some .quit => quit := true
    | some (.key k) => if k == keyEscape then quit := true else d := d.step (.key k)
    | some e => d := d.step e
    | none => pure ()
    raw ← Host.event 0
  if quit then return
  render c d.view
  Host.present c
  run c d (frames.map (· - 1))

-- The pure world, driven by a script of events instead of a person.
def test (c : Canvas) : IO Unit := do
  let grab := Event.press 300 (160 + 10)          -- Clock's title
  let script := [grab, .motion 700 500, .release 700 500,
                 .key keyN,                         -- a window at the pointer
                 .press (80 + 420 - 15) (70 + 14)]  -- REPL's close box
  let d := script.foldl Desktop.step start
  IO.println s!"after the script: {d.now.windows.map (·.title)}, \
    focus {d.now.focus}, {d.past.length} earlier worlds"
  let clock := d.now.windows.find? (·.title == "Clock")
  IO.println s!"Clock at {clock.map (·.x)} {clock.map (·.y)}; \
    in the start world still at {(start.now.windows.find? (·.title == "Clock")).map (·.x)}"
  render c d.view; c.savePng "after-script.png"
  let d := (d.step (.key keyU)).step (.key keyU)
  IO.println s!"after two undos: {d.now.windows.map (·.title)}"
  render c d.view; c.savePng "after-undo.png"

def main (args : List String) : IO Unit := do
  let c ← Canvas.new screenW.toUInt32 screenH.toUInt32
  match args with
  | ["--test"] => test c
  | ["--frames", n] =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c start n.toNat?
  | _ =>
    Host.open "Lean Machine" screenW.toUInt32 screenH.toUInt32
    run c start none
