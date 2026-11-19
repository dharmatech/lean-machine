# A slider, made in the REPL

`Slider` is a widget: a value between two ends, picked by dragging a
knob along a track. It's a value, like an app, and an app keeps it in
its state. Here is an app that is only a slider, with a circle as wide
as the slider says. Type each line into the REPL and press Enter:

```lean
def box : Rect := ⟨20, 20, 300, Slider.height⟩
def look (s : Slider) (w h : Float) : Picture := .group [s.view box, .circle (w / 2) (h / 2 + 20) s.value 0x9ece6a]
launch (App.of "Size" ({ lo := 1, hi := 80, value := 20 } : Slider) (·.heard box) look)
```

- `box` is where the slider goes in the window: 20 from the left and
  the top, 300 wide, as tall as a slider is meant to be.
- `look` draws the slider in its box, and a green circle under it, the
  slider's value its radius.
- The app's state is the slider itself, from 1 to 80, at 20. Every
  event goes to `heard`, with the same box, which says what the slider
  becomes, or `none` if the event isn't about it.

A window titled Size opens beside the REPL. Things to try:
- Press anywhere on the track: the knob jumps there, white while you
  hold it, and the circle grows or shrinks.
- Hold it and drag: the circle follows. Drag out of the window, to the
  right or below it: the knob stops at the end, and follows again when
  you come back.
- Let go, then press Ctrl+Shift+Z: one undo takes back the whole drag,
  however far it went.
- Launch another, on a cube:

  ```lean
  launch (App.of "Cube" ({ lo := 1, hi := 80, value := 20, scale := .cube } : Slider) (·.heard box) look)
  ```

  Halfway along is now 1 + 79 / 8, about 11: the small sizes get most
  of the track. Boids' weights will use this scale.

## Where next

- Two sliders: keep a pair as the state, give each a box of its own,
  and pass an event to one, then the other:
  `(a.heard box1 e).map (·, b) <|> (b.heard box2 e).map (a, ·)`.
- [An app hears a drag](../design/world/drags.md): how a press, the
  motions after it and the release reach an app.
- [A slider is a value in a box the app gives it](../design/widgets/slider.md)

[↑ Explore](README.md)
