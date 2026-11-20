import LeanMachine.Picture
import LeanMachine.World
import Std.Time

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
@[extern "sv_mono"] opaque Canvas.mono (c : @& Canvas)
  (x y size advance : Float) (rgb : UInt32) (s : @& String) : IO Unit
-- The monospace font's own advance, in ems, to compare with `monoAdvance`.
@[extern "sv_mono_em"] opaque Canvas.monoEm (c : @& Canvas) : IO Float
@[extern "sv_save"] opaque Canvas.save (c : @& Canvas) : IO Unit
@[extern "sv_restore"] opaque Canvas.restore (c : @& Canvas) : IO Unit
@[extern "sv_translate"] opaque Canvas.translate (c : @& Canvas)
  (dx dy : Float) : IO Unit
@[extern "sv_clip"] opaque Canvas.clip (c : @& Canvas)
  (x y w h : Float) : IO Unit
@[extern "sv_save_png"] opaque Canvas.savePng (c : @& Canvas)
  (path : @& String) : IO Unit

-- The window, `w` by `h`, which the user can resize, down to `leastW` by
-- `leastH`, and maximize.
@[extern "sv_host_open"] opaque Host.open (title : @& String)
  (w h leastW leastH : UInt32) : IO Unit
@[extern "sv_host_present"] opaque Host.present (c : @& Canvas) : IO Unit
-- Whether the window fills the screen, with no frame or title (false
-- before `Host.open`), and the window put in full screen or taken out.
-- Either way SDL says the window was resized.
@[extern "sv_host_fullscreen"] opaque Host.fullscreen : IO Bool
@[extern "sv_host_set_fullscreen"] opaque Host.setFullscreen (on : Bool) : IO Unit
-- Ends the loop's wait for events. Any thread may call it: a run calls it
-- when it ends. Does nothing before `Host.open`.
@[extern "sv_host_wake"] opaque Host.wake : IO Unit
-- The text on the clipboard, the one Ctrl+C and Ctrl+V use in other
-- programs: empty if there's none, or none that is text, and before
-- `Host.open`.
@[extern "sv_host_clipboard"] opaque Host.clipboard : IO String
-- The primary selection: the text last selected in any program, which a
-- middle click pastes. Empty if there's none, and before `Host.open`.
@[extern "sv_host_primary_selection"] opaque Host.primarySelection : IO String
-- Puts `text` in the primary selection, for a middle click here or in
-- other programs. Does nothing before `Host.open`.
@[extern "sv_host_set_primary_selection"] opaque Host.setPrimarySelection (text : @& String) :
  IO Unit
-- Puts `text` on the clipboard, for a paste here or in other programs.
-- Does nothing before `Host.open`.
@[extern "sv_host_set_clipboard"] opaque Host.setClipboard (text : @& String) : IO Unit
-- An event as `sv_host_event` in shim.c hands it back: numbers
-- [kind, a, b, c, d], and the text of a text event (empty for the others).
-- Text can't travel in a `FloatArray`, and two fields keep one call per
-- event.
structure RawEvent where
  nums : FloatArray
  text : String

@[extern "sv_host_event"] opaque Host.event (timeoutMs : UInt32) : IO RawEvent

-- A key from SDL's keycode. A key with a character on it has that
-- character's code; the others have codes from 0x40000000 up. SDL may give
-- a letter in upper case with Shift held, so letters are made lower case.
def Key.ofSDL (code : UInt32) : Key :=
  match code.toNat with
  | 13 | 0x40000058 => .enter        -- Return, and Enter on the keypad
  | 9 => .tab
  | 8 => .backspace
  | 127 => .delete
  | 0x40000049 => .insert
  | 27 => .escape
  | 0x4000004F => .right
  | 0x40000050 => .left
  | 0x40000051 => .down
  | 0x40000052 => .up
  | 0x4000004A => .home
  | 0x4000004D => .«end»
  | 0x4000004B => .pageUp
  | 0x4000004E => .pageDown
  | 0x40000044 => .f11
  | n => if 32 ≤ n && n < 127 then .char (Char.ofNat n).toLower
         else .other code

-- SDL's modifier bits: left and right Shift 0x3, Ctrl 0xC0, Alt 0x300.
def Mods.ofSDL (bits : UInt32) : Mods :=
  { shift := bits &&& 0x3 != 0, ctrl := bits &&& 0xC0 != 0,
    alt := bits &&& 0x300 != 0 }

-- For a button, c is SDL's number for it: 1 left, 2 middle, 3 right, and for a
-- press d is how many clicks in a row it makes; for the wheel, c is how
-- far it turned. The window resized brings its new size in a and b. A
-- key brings its code and modifiers in a and b; text, the modifiers held
-- as it was typed. Text typed with Ctrl held is a command, not text: the
-- key event that came with it carries it.
def Event.decode (r : RawEvent) : Option Event :=
  let a := r.nums
  let x := a.get! 1
  let y := a.get! 2
  let button := a.get! 3
  let clicks := if a.size > 4 then (a.get! 4).toUInt32.toNat else 1
  match (a.get! 0).toUInt32 with
  | 1 => some .quit
  | 2 => if button == 1 then some (.press x y (max 1 clicks))
         else if button == 2 then some (.middle x y)
         else if button == 3 then some (.menu x y)
         else none
  | 3 => if button == 1 then some (.release x y) else none
  | 4 => some (.motion x y)
  | 5 => some (.key (Key.ofSDL x.toUInt32) (Mods.ofSDL y.toUInt32))
  | 6 => if (Mods.ofSDL x.toUInt32).ctrl || r.text.isEmpty then none
         else some (.text r.text)
  | 8 => some (.wheel x y button)   -- c is how far it turned
  | 9 => some (.screen x y)
  | _ => none   -- 7 is a wake (`Host.wake`): the loop goes on

-- Runs `act`, then puts back the canvas's origin and clip as they were.
def Canvas.saved (c : Canvas) (act : IO Unit) : IO Unit := do
  c.save
  try act finally c.restore

-- The local time of day, and the milliseconds left in its second. Lean's
-- Std.Time reads it, no C: about 80 µs a call.
def localTime : IO (TimeOfDay × Nat) := do
  let t ← Std.Time.PlainTime.now
  let ms := (t.nanosecond.val / 1000000).toNat
  return ({ hour := t.hour.val.toNat, minute := t.minute.val.toNat,
            second := t.second.val.toNat }, 1000 - ms)

partial def render (c : Canvas) : Picture → IO Unit
  | .rect x y w h r rgb => c.fillRect x y w h r rgb
  | .circle cx cy r rgb => c.circle cx cy r rgb
  | .ring cx cy r width rgb => c.ring cx cy r width rgb
  | .line x1 y1 x2 y2 width rgb => c.line x1 y1 x2 y2 width rgb
  | .text x y size rgb s => c.text x y size rgb s
  | .textIn x y w h size align rgb s => c.textIn x y w h size align rgb s
  | .mono x y size rgb s => c.mono x y size (monoAdvance size) rgb s
  | .translate dx dy p => c.saved do c.translate dx dy; render c p
  | .clip x y w h p => c.saved do c.clip x y w h; render c p
  | .group ps => ps.forM (render c)

end LeanMachine
