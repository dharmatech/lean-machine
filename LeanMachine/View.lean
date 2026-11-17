import LeanMachine.Picture
import LeanMachine.World
import LeanMachine.Desktop

/-! # The view: a desktop as a picture

Pure: it returns a `Picture` and draws nothing. -/

namespace LeanMachine

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

end LeanMachine
