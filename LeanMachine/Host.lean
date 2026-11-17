import LeanMachine.Picture
import LeanMachine.World

/-! # The host: a canvas and one window (shim.c)

The only module that calls C. Cairo draws into a canvas in memory; SDL3
shows it in one window and hands back events. -/

namespace LeanMachine

opaque CanvasPointed : NonemptyType
def Canvas := CanvasPointed.type
instance : Nonempty Canvas := CanvasPointed.property

@[extern "sv_canvas_new"] opaque Canvas.new (w h : UInt32) : IO Canvas
@[extern "sv_fill_rect"] opaque Canvas.fillRect (c : @& Canvas)
  (x y w h radius : Float) (rgb : UInt32) : IO Unit
@[extern "sv_circle"] opaque Canvas.circle (c : @& Canvas)
  (cx cy r : Float) (rgb : UInt32) : IO Unit
@[extern "sv_ring"] opaque Canvas.ring (c : @& Canvas)
  (cx cy r width : Float) (rgb : UInt32) : IO Unit
@[extern "sv_line"] opaque Canvas.line (c : @& Canvas)
  (x1 y1 x2 y2 width : Float) (rgb : UInt32) : IO Unit
@[extern "sv_text"] opaque Canvas.text (c : @& Canvas)
  (x y size : Float) (rgb : UInt32) (s : @& String) : IO Unit
@[extern "sv_text_in"] opaque Canvas.textIn (c : @& Canvas)
  (x y w h size : Float) (align : Align) (rgb : UInt32) (s : @& String) : IO Unit
@[extern "sv_save"] opaque Canvas.save (c : @& Canvas) : IO Unit
@[extern "sv_restore"] opaque Canvas.restore (c : @& Canvas) : IO Unit
@[extern "sv_translate"] opaque Canvas.translate (c : @& Canvas)
  (dx dy : Float) : IO Unit
@[extern "sv_clip"] opaque Canvas.clip (c : @& Canvas)
  (x y w h : Float) : IO Unit
@[extern "sv_save_png"] opaque Canvas.savePng (c : @& Canvas)
  (path : @& String) : IO Unit

@[extern "sv_host_open"] opaque Host.open (title : @& String)
  (w h : UInt32) : IO Unit
@[extern "sv_host_present"] opaque Host.present (c : @& Canvas) : IO Unit
@[extern "sv_host_event"] opaque Host.event (timeoutMs : UInt32) : IO FloatArray

-- An event as `Host.event` returns it: [kind, a, b, c], as
-- `sv_host_event` in shim.c writes it.
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

-- Runs `act`, then puts back the canvas's origin and clip as they were.
def Canvas.saved (c : Canvas) (act : IO Unit) : IO Unit := do
  c.save
  try act finally c.restore

partial def render (c : Canvas) : Picture → IO Unit
  | .rect x y w h r rgb => c.fillRect x y w h r rgb
  | .circle cx cy r rgb => c.circle cx cy r rgb
  | .ring cx cy r width rgb => c.ring cx cy r width rgb
  | .line x1 y1 x2 y2 width rgb => c.line x1 y1 x2 y2 width rgb
  | .text x y size rgb s => c.text x y size rgb s
  | .textIn x y w h size align rgb s => c.textIn x y w h size align rgb s
  | .translate dx dy p => c.saved do c.translate dx dy; render c p
  | .clip x y w h p => c.saved do c.clip x y w h; render c p
  | .group ps => ps.forM (render c)

end LeanMachine
