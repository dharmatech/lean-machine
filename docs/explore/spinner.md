# A spinner, made in the REPL

An app can ask for frames: 60 a second, each with a clock's
milliseconds. Here is one made in the REPL, a line that turns once
every π seconds. Type each line into the REPL and press Enter:

```lean
def hand (ms : Nat) (w h : Float) : Picture := let a := ms.toFloat / 500; .line (w / 2) (h / 2) (w / 2 + 80 * a.cos) (h / 2 + 80 * a.sin) 4 0xf7768e
def hear : Nat → AppEvent → Option Nat | _, .frame ms => some ms | _, _ => none
launch (App.of "Spin" 0 hear hand (animating := fun _ => true))
```

- `hand` draws the line at the angle of a time, in a window `w` by `h`.
- `hear` keeps the time of the last frame and ignores everything else.
- `animating := fun _ => true` says the app wants frames whatever its
  state.

A window titled Spin opens beside the REPL, its line turning. Things to
try:
- Minimize it (the yellow box, or Ctrl+Shift+H): it stops. Bring it
  back from the taskbar, and it goes on from where the clock is now.
- Resize it: the line stays in the middle.
- Launch it again: two spinners, in step, since both read the same
  clock.

## Where next

- Make it stop on a click. Keep `(ms, on)` as the state, flip `on` on
  a press, and pass `animating := (·.2)`. It wants frames only while
  it's on.
- [An app says from its state whether it animates](../design/world/frames.md):
  how frames work.
- [A frame costs more when frames are apart](../design/drawing/frames-apart.md)

[↑ Explore](README.md)
