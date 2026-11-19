# The rules panel keeps only which slider is held

Schevana's rules were a window of their own, beside the flock's, that
read and set the flock window's properties. In Lean Machine a window
can't open another and keep talking to it: an app changes only its own
window, and only code run from a REPL opens windows, without learning
their ids. So the rules are a panel in the Boids window, at its right.
A window of their own would need the desktop to let windows send each
other messages first ([ideas](../../ideas.md)).

The panel has a `Row` for the count and one for each `Setting`. It keeps
no sliders. `State.slider r` makes row `r`'s slider when it's needed,
its value from the rules or the flock's size, and held if `State.held`
is `r`. That is all the panel's own state: which row is being dragged.
So the rules and the count stay the only record of the values, and a
slider shows them whoever changed them: a drag, R or D, or a speed
limit pushed by the other.

`State.pointed` passes a press, a motion or a release to the held row's
slider, or with none held, to the slider a press is on. The slider says
what it becomes, and the state takes its value (`State.setRow`) and
whether it's held. `sliderBox w i` is where row `i`'s slider is in a
body `w` wide, for the view and for a press alike.

The panel shows at first, as Niva's and Schevana's did, and the window
opens 360 pixels wider for it, so the field is still 760 wide. H hides
it, and the field takes the whole body. The values read as Schevana's
did (`Setting.readout`): speeds to a tenth, angles in degrees, weights
to four places. The weights and the count go on a cube
([A cube for values that span orders of magnitude](../widgets/cube.md)).

The labels, readouts and layout are in Boids.lean, which reloads, not
in the compiled Rules.lean: a reload can change how the panel looks
while the flock flies.

[↑ Boids](README.md)
