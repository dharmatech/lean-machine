# A cube for values that span orders of magnitude

Boids' weights are useful from about 0.001 to 1: separation is 0.001
by default. On an even track from 0 to 1, everything up to 0.01 is in
the first hundredth of it, a pixel or two. A log scale spreads them
out, but can't reach 0, and 0 turns a rule off.

Niva's Boids had a log slider. Schevana's put a weight on a cube
instead, and so does Lean Machine (`Slider.Scale.cube`): the value grows
as the cube of the way along. Halfway along is an eighth of the way
between the ends, a tenth of the way along is a thousandth, and 0 is
at the start. `Slider.placeOf` goes back with `Float.cbrt`.

[↑ Widgets](README.md)
