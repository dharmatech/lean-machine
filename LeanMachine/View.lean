import LeanMachine.Picture
import LeanMachine.World
import LeanMachine.Desktop

/-! # The view: a desktop as a picture

Pure: it returns a `Picture` and draws nothing. -/

namespace LeanMachine

def litRgb : UInt32 := 0x7dcfff   -- an edge the pointer would grab, or is dragging

-- A window, its edges `lit` lit. The grip in the body's bottom right
-- corner, drawn over the app, says that the window can be resized. On the
-- title, the close box, and left of it the box that maximizes the window,
-- with a hole in it while the window is maximized, to restore it.
def Win.view (w : Win) (focused : Bool) (lit : Edges := {}) : Picture :=
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
    .rect (right - 22) (w.y + 7) 14 14 3 (if focused then 0xf7768e else 0x414868),
    .rect (right - 42) (w.y + 7) 14 14 3 (if focused then 0x9ece6a else 0x414868),
    if w.maximized then .rect (right - 38) (w.y + 11) 6 6 1 titleRgb else .group [],
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

def Desktop.view (d : Desktop) : Picture :=
  let world := d.now
  let lit := world.lit
  .group ([.rect 0 0 screenW screenH 0 0x24283b] ++
    world.windows.map (fun w => w.view (w.id == world.focus)
      (match lit with
       | some (id, es) => if id == w.id then es else {}
       | none => {})) ++
    [.rect 0 (screenH - barH) screenW barH 0 0x16161e,
     .text 14 (screenH - 10) 13 0x7aa2f7
       s!"{d.past.length} earlier worlds   ·   \
          right-click or Ctrl+Shift+N: open an app   ·   drag a title or an edge   ·   \
          click in a window, then type   ·   boxes on a title: maximize, close   ·   \
          Ctrl+Shift+Z undo   ·   Esc quits"] ++
    world.menu.toList.map world.menuView)

end LeanMachine
