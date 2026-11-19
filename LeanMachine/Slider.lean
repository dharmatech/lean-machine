import LeanMachine.App

/-! # A slider: a value picked by dragging a knob along a track

A widget is a value, like an app. An app that has a slider keeps it in
its state, passes it the events it hears (`heard`), and draws it in its
view (`view`). Where the slider is, its box, is the app's to say: it
gives the same box to both, from its own size, so the slider goes where
the app lays it out.

A press on the slider grabs the knob and puts it under the pointer.
Then the knob follows the pointer, wherever the pointer goes, until the
button is let go, and stops at the ends of the track. -/

namespace LeanMachine

-- How a slider's values go along its track.
inductive Slider.Scale where
  | linear   -- evenly: halfway along is halfway between the ends
  -- As the cube of the way along: halfway along is an eighth of the way
  -- between the ends. For values whose useful sizes span orders of
  -- magnitude: the small ones get most of the track, as on a log scale,
  -- and 0 is still on it.
  | cube
  deriving BEq, Repr, Inhabited

-- A value from `lo` to `hi`, and whether its knob is being dragged.
structure Slider where
  lo : Float
  hi : Float
  value : Float
  scale : Slider.Scale := .linear
  held : Bool := false
  deriving BEq, Repr

namespace Slider

-- How tall a slider's box is meant to be, and its knob's radius. The
-- knob's center goes from `knob` inside the box's left edge to `knob`
-- inside its right, so the knob is always inside the box.
def height : Float := 20
def knob : Float := 7

def trackRgb : UInt32 := 0x3b4261
def filledRgb : UInt32 := 0x7aa2f7
def knobRgb : UInt32 := 0xa9b1d6
def heldRgb : UInt32 := 0xffffff

-- Where `v` is along the track, from 0 at `lo` to 1 at `hi`.
def placeOf (s : Slider) (v : Float) : Float :=
  let t := max 0 (min 1 ((v - s.lo) / (s.hi - s.lo)))
  match s.scale with
  | .linear => t
  | .cube => t.cbrt

-- The value `t` of the way along the track.
def valueAt (s : Slider) (t : Float) : Float :=
  let t := max 0 (min 1 t)
  s.lo + (s.hi - s.lo) * match s.scale with
    | .linear => t
    | .cube => t * t * t

-- How far along the track the pointer at `x` is, in a box `r`: 0 left
-- of the track, 1 right of it.
def along (r : Rect) (x : Float) : Float :=
  max 0 (min 1 ((x - (r.x + knob)) / (r.w - 2 * knob)))

-- The knob's center across a box `r`.
def knobX (s : Slider) (r : Rect) : Float :=
  r.x + knob + s.placeOf s.value * (r.w - 2 * knob)

-- The slider after an event, in a box `r`; `none` if the event doesn't
-- change it. A press in the box grabs the knob there. While it's held,
-- a motion anywhere moves it, and a release lets it go, as does a press
-- outside the box: a release can go to another window, if the focus
-- moved away during the drag.
def heard (s : Slider) (r : Rect) : AppEvent → Option Slider
  | .press x y =>
    if r.contains x y then some { s with value := s.valueAt (along r x), held := true }
    else if s.held then some { s with held := false }
    else none
  | .motion x _ =>
    let value := s.valueAt (along r x)
    if s.held && value != s.value then some { s with value } else none
  | .release .. => if s.held then some { s with held := false } else none
  | _ => none

-- The track, filled from its start to the knob, and the knob, white
-- while it's held, across the middle of a box `r`.
def view (s : Slider) (r : Rect) : Picture :=
  let y := r.y + r.h / 2
  let x := s.knobX r
  .group [.rect (r.x + knob - 2) (y - 2) (r.w - 2 * knob + 4) 4 2 trackRgb,
          .rect (r.x + knob - 2) (y - 2) (x - r.x - knob + 4) 4 2 filledRgb,
          .circle x y knob (if s.held then heldRgb else knobRgb)]

end Slider

/-! ## Checks, run as the module builds -/

-- A box with a track 200 long, from x = 7 to 207, and two sliders.
private def box : Rect := ⟨0, 0, 200 + 2 * Slider.knob, Slider.height⟩
private def tens : Slider := { lo := 0, hi := 10, value := 0 }
private def cubed : Slider := { lo := 0, hi := 0.2, value := 0, scale := .cube }

-- `s` after the events `es`.
private def drag (s : Slider) (es : List AppEvent) : Slider :=
  es.foldl (fun s e => (s.heard box e).getD s) s

-- A press halfway along grabs the knob there: 5, from 0 to 10. On a
-- cube, an eighth of the way: 0.025, from 0 to 0.2.
#guard tens.heard box (.press 107 10) == some { tens with value := 5, held := true }
#guard (cubed.heard box (.press 107 10)).map (·.value) == some 0.025

-- Held, the knob follows the pointer, above or below the box too, and
-- stops at the ends.
#guard (drag tens [.press 107 10, .motion 57 300]).value == 2.5
#guard (drag tens [.press 107 10, .motion 500 10]).value == 10
#guard (drag tens [.press 107 10, .motion (-50) 10]).value == 0

-- Not held, a motion changes nothing; a release lets go.
#guard (tens.heard box (.motion 57 10)).isNone
#guard let s := drag tens [.press 107 10, .release 107 10]
  !s.held && (s.heard box (.motion 57 10)).isNone

-- A press outside the box misses it, unless it's held: then it lets go.
#guard (tens.heard box (.press 107 30)).isNone
#guard (drag tens [.press 107 10, .press 107 30]) == { tens with value := 5 }

-- A value's place on the track gives the value back.
#guard [0, 0.001, 0.05, 0.1, 0.2].all fun v =>
  (cubed.valueAt (cubed.placeOf v) - v).abs < 1e-12
#guard [0, 2.5, 10].all fun v => tens.valueAt (tens.placeOf v) == v

end LeanMachine
