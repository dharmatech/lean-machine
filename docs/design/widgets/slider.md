# A slider is a value in a box the app gives it

Schevana's widgets are immediate: a window's draw procedure calls
`ui-slider` with an id, a place and a procedure to set the value, and a
mutable `ui` keeps which one is held. Lean Machine mutates nothing, and
has no kit for apps to share state with. So a widget is a value, as an
app is, and the app keeps it in its state.

`Slider` (LeanMachine/Slider.lean) holds its ends, its value, its
scale, and whether its knob is held. `heard r e` is the slider after
the event `e`, or `none` if the event doesn't change it, and `view r`
draws it. Both take its box, `r`, a `Rect` in the app's coordinates:
the slider doesn't know where it is. The app works the box out from its
size, which it hears ([An app hears its size](../world/app-size.md)),
and gives the same box to both, so the knob is drawn where a press
finds it. The same slider can be drawn at any width, and a panel of
sliders is a function from the app's size to a box for each.

`Rect` moved from World.lean to Picture.lean for this: it is a window's
place on the screen, or a widget's in a window's body.

The knob's center stays a knob's radius inside the box's ends, so the
knob is never cut off; the track is where its center can go. A press on
the track puts the knob under the pointer, rather than waiting for the
knob itself to be grabbed.

The REPLs' Lean imports the module, compiled, as it does Boids'
simulation, so a REPL can make a slider, and a reloaded app can have
some.

How the pointer reaches it: [An app hears a drag](../world/drags.md).
Boids' rules are a column of them, made from its state as it's drawn
([The rules panel keeps only which slider is held](../boids/rules-panel.md)).

[↑ Widgets](README.md)
