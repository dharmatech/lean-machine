import LeanMachine.App

/-! # Clock: an analog face, and the time in digits under it

After Schevana's `apps/clock.ss`. The face is a pure function of the time
and the size. The app keeps the time the last tick brought, and changes
only when the second does. -/

namespace LeanMachine

-- "09:05:03"
def TimeOfDay.digits (t : TimeOfDay) : String :=
  let two (n : Nat) := if n < 10 then s!"0{n}" else toString n
  s!"{two t.hour}:{two t.minute}:{two t.second}"

def clockFace (t : TimeOfDay) (w h : Float) : Picture :=
  let digitsH : Float := 34
  let size := min w (h - digitsH)
  let r := max 10 (size / 2 - 16)
  let cx := w / 2
  let cy := 8 + size / 2
  -- The point `len` from the center, `a` radians clockwise from 12.
  let toward (a len : Float) : Float × Float :=
    (cx + len * a.sin, cy - len * a.cos)
  let hand (a len width : Float) (rgb : UInt32) : Picture :=
    let (x, y) := toward a len
    .line cx cy x y width rgb
  -- One of the 60 marks; every fifth is longer and brighter.
  let mark (i : Nat) : Picture :=
    let a := i.toFloat * pi / 30
    let major := i % 5 == 0
    let (x1, y1) := toward a (if major then r - 10 else r - 4)
    let (x2, y2) := toward a r
    .line x1 y1 x2 y2 (if major then 2.5 else 1)
      (if major then 0xc0caf5 else 0x565f89)
  let hours := (t.hour % 12).toFloat + t.minute.toFloat / 60
  let minutes := t.minute.toFloat + t.second.toFloat / 60
  .group ([.circle cx cy (r + 8) 0x24283b, .ring cx cy (r + 8) 2 0x414868] ++
    (List.range 60).map mark ++
    [hand (hours * pi / 6) (r * 0.52) 5 0xc0caf5,
     hand (minutes * pi / 30) (r * 0.78) 3.5 0x9aa5ce,
     hand (t.second.toFloat * pi / 30) (r * 0.86) 1.5 0xf7768e,
     .circle cx cy 5 0xf7768e,
     .textIn 0 (h - digitsH) w digitsH 16 .center 0x9aa5ce t.digits])

-- Starts at midnight. The loop ticks before every frame, so a clock shows
-- the right time from the first frame it's in.
def clock : App :=
  App.of "Clock" ({ hour := 0, minute := 0, second := 0 } : TimeOfDay)
    (fun shown e => match e with
      | .tick t => if t == shown then none else some t
      | _ => none)
    clockFace (size := (230, 259))

end LeanMachine
