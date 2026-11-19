/-! # Pictures: what the view makes and the host draws, as plain data -/

namespace LeanMachine

-- Lean's `Float` has `sin` and `cos` but no π.
def pi : Float := 3.141592653589793

-- How far apart `mono` puts characters: each sits in a cell this wide.
-- 0.6 em is the advance of DejaVu Sans Mono (0.602 em) and most other
-- monospace fonts. Lean, not the font, decides it, so a view can measure
-- monospace text and place a cursor without asking Cairo.
def monoAdvance (size : Float) : Float := 0.6 * size

-- A box: its top left corner, and its size. A window's place on the
-- screen, or a widget's in a window's body.
structure Rect where
  x : Float
  y : Float
  w : Float
  h : Float
  deriving BEq, Inhabited, Repr

def Rect.contains (r : Rect) (x y : Float) : Bool :=
  r.x ≤ x && x < r.x + r.w && r.y ≤ y && y < r.y + r.h

-- Where text sits across its box. Top to bottom it is always centered.
inductive Align where
  | left | center | right

inductive Picture where
  | rect (x y w h radius : Float) (rgb : UInt32)         -- filled
  | circle (cx cy r : Float) (rgb : UInt32)              -- filled
  | ring (cx cy r width : Float) (rgb : UInt32)          -- a circle's outline
  | line (x1 y1 x2 y2 width : Float) (rgb : UInt32)      -- round ends
  | text (x y size : Float) (rgb : UInt32) (s : String)  -- from its baseline
  | textIn (x y w h size : Float) (align : Align) (rgb : UInt32) (s : String)
  -- Monospace text from its baseline; character i starts at
  -- x + i * monoAdvance size.
  | mono (x y size : Float) (rgb : UInt32) (s : String)
  -- The picture with its origin moved to (dx, dy).
  | translate (dx dy : Float) (p : Picture)
  -- The picture, cut to the box (x, y, w, h).
  | clip (x y w h : Float) (p : Picture)
  | group (ps : List Picture)

end LeanMachine
