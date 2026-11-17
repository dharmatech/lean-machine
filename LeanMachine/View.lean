import LeanMachine.Picture
import LeanMachine.World
import LeanMachine.Desktop

/-! # The view: a desktop as a picture

Pure: it returns a `Picture` and draws nothing. -/

namespace LeanMachine

def Win.view (w : Win) (focused : Bool) : Picture :=
  .group [
    .rect w.x w.y w.w w.h 8 (if focused then 0xbb9af7 else 0x565f89),
    .rect w.bodyX w.bodyY w.bodyW w.bodyH 6 0x1a1b26,
    .text (w.x + 12) (w.y + 19) 14 0x1a1b26 w.title,
    .rect (w.x + w.w - 22) (w.y + 7) 14 14 3
      (if focused then 0xf7768e else 0x414868),
    -- The app draws in its own coordinates, cut to the body.
    .translate w.bodyX w.bodyY
      (.clip 0 0 w.bodyW w.bodyH (w.app.view w.bodyW w.bodyH)) ]

-- The menu: a line that says what it does, then an item for each app in
-- the catalog. The item under the pointer is lit.
def World.menuView (world : World) (m : Menu) : Picture :=
  let lit := world.itemAt? m world.mouseX world.mouseY
  .group ([.rect m.x m.y menuW world.menuH 7 0x565f89,
           .rect (m.x + 1) (m.y + 1) (menuW - 2) (world.menuH - 2) 6 0x1a1b26,
           .textIn (m.x + 14) m.y (menuW - 28) menuHeadH 12 .left 0x565f89
             "Open an app"] ++
    world.catalog.zipIdx.map fun (app, i) =>
      let y := m.itemY i
      let on := lit == some i
      .group ((if on then [.rect (m.x + 4) y (menuW - 8) itemH 4 0x414868]
               else []) ++
        [.textIn (m.x + 14) y (menuW - 28) itemH 14 .left
           (if on then 0xc0caf5 else 0x9aa5ce) app.title]))

def Desktop.view (d : Desktop) : Picture :=
  let world := d.now
  .group ([.rect 0 0 screenW screenH 0 0x24283b] ++
    world.windows.map (fun w => w.view (w.id == world.focus)) ++
    [.rect 0 (screenH - barH) screenW barH 0 0x16161e,
     .text 14 (screenH - 10) 13 0x7aa2f7
       s!"{d.past.length} earlier worlds   ·   \
          right-click or Ctrl+Shift+N: open an app   ·   drag a title   ·   \
          click in a window, then type   ·   click the box to close   ·   \
          Ctrl+Shift+Z undo   ·   Esc quits"] ++
    world.menu.toList.map world.menuView)

end LeanMachine
