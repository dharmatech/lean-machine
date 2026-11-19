import LeanMachine.Picture
import LeanMachine.World
import LeanMachine.Desktop

/-! # The view: a desktop as a picture

Pure: it returns a `Picture` and draws nothing. -/

namespace LeanMachine

def litRgb : UInt32 := 0x7dcfff   -- an edge the pointer would grab, or is dragging

-- What each box on a title does, drawn on it in the dark of a body, a
-- box 14 pixels square centered at (cx, cy): × closes, − minimizes, a
-- square maximizes, and two squares, one behind the other, restore.
def closeGlyph (cx cy : Float) : Picture :=
  .group [.line (cx - 3.5) (cy - 3.5) (cx + 3.5) (cy + 3.5) 1.5 0x1a1b26,
          .line (cx - 3.5) (cy + 3.5) (cx + 3.5) (cy - 3.5) 1.5 0x1a1b26]
def minGlyph (cx cy : Float) : Picture :=
  .rect (cx - 4) (cy - 1) 8 2 0 0x1a1b26
-- An outlined square, its corner at (x, y), `s` wide, inside a box of colour `rgb`.
def squareGlyph (x y s : Float) (rgb : UInt32) : Picture :=
  .group [.rect x y s s 0 0x1a1b26, .rect (x + 1.5) (y + 1.5) (s - 3) (s - 3) 0 rgb]
def maxGlyph (cx cy : Float) : Picture := squareGlyph (cx - 4) (cy - 4) 8 0x9ece6a
def restoreGlyph (cx cy : Float) : Picture :=
  .group [squareGlyph (cx - 2) (cy - 4.5) 6.5 0x9ece6a,
          .rect (cx - 4.5) (cy - 2) 6.5 6.5 0 0x9ece6a,
          squareGlyph (cx - 4.5) (cy - 2) 6.5 0x9ece6a]

-- A window, its edges `lit` lit. The grip in the body's bottom right
-- corner, drawn over the app, says that the window can be resized. On the
-- title, the close box; left of it the box that maximizes the window,
-- with a hole in it while the window is maximized, to restore it; and
-- left of that the box that minimizes it. With the pointer on any of
-- them (`boxes`), all three are in colour, focused or not, and each
-- shows what it does.
def Win.view (w : Win) (focused : Bool) (lit : Edges := {}) (boxes : Bool := false) :
    Picture :=
  let titleRgb : UInt32 := if focused then 0xbb9af7 else 0x565f89
  let right := w.x + w.w
  let bottom := w.y + w.h
  -- The lit edges, short of the rounded corners.
  let bars := [(lit.left, Picture.rect w.x (w.y + 6) frame (w.h - 12) 1 litRgb),
               (lit.right, .rect (right - frame) (w.y + 6) frame (w.h - 12) 1 litRgb),
               (lit.top, .rect (w.x + 6) w.y (w.w - 12) frame 1 litRgb),
               (lit.bottom, .rect (w.x + 6) (bottom - frame) (w.w - 12) frame 1 litRgb)]
  let gripRgb := if lit.right && lit.bottom then litRgb
    else if focused then 0x737aa2 else 0x414868
  let gx := w.bodyX + w.bodyW
  let gy := w.bodyY + w.bodyH
  let grip := [4, 8, 12].map fun (k : Float) => Picture.line (gx - k) (gy - 2) (gx - 2) (gy - k) 1.5 gripRgb
  .group ([
    .rect w.x w.y w.w w.h 8 titleRgb,
    .rect w.bodyX w.bodyY w.bodyW w.bodyH 6 0x1a1b26,
    .text (w.x + 12) (w.y + 19) 14 0x1a1b26 w.title,
    .rect (right - 22) (w.y + 7) 14 14 3 (if focused || boxes then 0xf7768e else 0x414868),
    .rect (right - 42) (w.y + 7) 14 14 3 (if focused || boxes then 0x9ece6a else 0x414868),
    .rect (right - 62) (w.y + 7) 14 14 3 (if focused || boxes then 0xe0af68 else 0x414868),
    if boxes then
      .group [closeGlyph (right - 15) (w.y + 14), minGlyph (right - 55) (w.y + 14),
              if w.maximized then restoreGlyph (right - 35) (w.y + 14)
              else maxGlyph (right - 35) (w.y + 14)]
    else if w.maximized then .rect (right - 38) (w.y + 11) 6 6 1 titleRgb else .group [],
    -- The app draws in its own coordinates, cut to the body.
    .translate w.bodyX w.bodyY
      (.clip 0 0 w.bodyW w.bodyH (w.app.view w.bodyW w.bodyH))] ++
    grip ++ bars.filterMap fun (on, p) => if on then some p else none)

-- The edges to light, and whose: those a resize is dragging, or with no
-- drag and no menu, those a press where the pointer is would grab.
def World.lit (world : World) : Option (Nat × Edges) :=
  match world.drag, world.menu with
  | some d, _ => if d.edges == .all then none else some (d.id, d.edges)
  | none, none => (world.grabAt world.mouseX world.mouseY).bind fun (w, es) =>
    if es.any then some (w.id, es) else none
  | none, some _ => none

-- The window whose title boxes show what they do: the one a press where
-- the pointer is would hit a box of, with no drag and no menu.
def World.boxesLit (world : World) : Option Nat :=
  match world.drag, world.menu with
  | none, none => (world.grabAt world.mouseX world.mouseY).bind fun (w, es) =>
    if !es.any && w.onBoxes world.mouseX world.mouseY then some w.id else none
  | _, _ => none

-- The menu: a line that says what it does, then an item for each app in
-- the catalog. The item under the pointer is lit.
def World.menuView (world : World) (m : Menu) : Picture :=
  let lit := world.itemAt? m world.mouseX world.mouseY
  .group ([.rect m.x m.y menuW world.menuH 7 0x565f89,
           .rect (m.x + 1) (m.y + 1) (menuW - 2) (world.menuH - 2) 6 0x1a1b26,
           .textIn (m.x + 14) m.y (menuW - 28) menuHeadH 12 .left 0x565f89
             "Open an app"] ++
    world.catalog.zipIdx.map fun ((_, app), i) =>
      let y := m.itemY i
      let on := lit == some i
      .group ((if on then [.rect (m.x + 4) y (menuW - 8) itemH 4 0x414868]
               else []) ++
        [.textIn (m.x + 14) y (menuW - 28) itemH 14 .left
           (if on then 0xc0caf5 else 0x9aa5ce) app.title]))

-- Window `w`'s button on the taskbar, at `x` and `bw` wide: a dot, then
-- the title, cut to the button. The focused window's is filled and
-- underlined, and one under the pointer filled more faintly; a minimized
-- window's dot and title are dim.
def Win.button (w : Win) (x bw : Float) (focused hovered : Bool) : Picture :=
  let fill : List Picture :=
    if focused then [.rect x (barY + 4) bw (barH - 8) 6 0x292e42,
                     .rect (x + 12) (barY + barH - 6) (bw - 24) 2 1 0xbb9af7]
    else if hovered then [.rect x (barY + 4) bw (barH - 8) 6 0x1f2335]
    else []
  .group (fill ++
    [.circle (x + 15) (barY + barH / 2) 4
       (if w.minimized then 0x414868 else if focused then 0xbb9af7 else 0x7aa2f7),
     .clip (x + 27) barY (bw - 36) barH
       (.textIn (x + 27) barY (bw - 36) barH barTextSize .left
         (if w.minimized then 0x565f89 else 0xc0caf5) w.title)])

-- The taskbar along the bottom, `earlier` the number of earlier worlds:
-- the windows' buttons, then the hint if it has room and the count, as
-- one text at the right, so that Cairo spaces them.
def World.barView (world : World) (earlier : Nat) : Picture :=
  let bar := world.taskbar
  let hovered := ((bar.buttonAt world.mouseX world.mouseY).map (·.id)).getD 0
  .group ([.rect 0 barY screenW barH 0 0x16161e] ++
    bar.buttons.map (fun (w, x) => w.button x bar.w (w.id == world.focus) (w.id == hovered)) ++
    [.textIn (screenW - countW - hintW) barY (countW + hintW - 14) barH barTextSize .right
       0x7aa2f7 ((if bar.hint then barHint ++ "   ·   " else "") ++ s!"{earlier} earlier worlds")])

def Desktop.view (d : Desktop) : Picture :=
  let world := d.now
  let lit := world.lit
  let boxes := world.boxesLit
  .group ([.rect 0 0 screenW screenH 0 0x24283b] ++
    world.visible.map (fun w => w.view (w.id == world.focus)
      (match lit with
       | some (id, es) => if id == w.id then es else {}
       | none => {})
      (boxes == some w.id)) ++
    [world.barView d.past.length] ++
    world.menu.toList.map world.menuView)

end LeanMachine
