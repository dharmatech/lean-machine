# Boids

Boids is a flock of birds, each steering by a few rules: toward the
middle of the birds it sees, along with their heading, and away from
any that come too close. Open it from the menu (right-click, Boids). A
flock of 150 flies over the window. Each bird is a yellow dot with a red
line toward where it is heading. Its rules are beside it.

With the Boids window focused:

| Key   | What it does |
|-------|--------------|
| R     | random rules, each picked within its range |
| D     | the default rules again |
| S     | scatter the flock anew, as many birds |
| Up    | 50 birds more, up to 2000 |
| Down  | 50 birds fewer, down to 10 |
| Space | pause, and go on |
| H     | hide the rules, and show them again |

The status line under the flock says how many birds there are and how
many frames a second the window gets, up to 60. With several hundred
birds (around 800 on the machine it was written on), or with heavy
random rules, stepping and drawing the flock take longer than a frame,
and the count drops.

While the flock flies, the desktop draws 60 frames a second. Paused or
minimized, it stops, and the desktop sleeps between events again.
Resizing the window resizes the field: birds that find themselves
outside it come back in at the opposite edge.

## The rules

Each row beside the flock is a slider: its name, then the slider, then
its value. Press on a slider and drag: the knob follows the pointer,
even out of the window, and the flock changes as you go. One
Ctrl+Shift+Z takes back a whole drag.

- **boids**: how many, from 10 to 2000.
- **cohesion**, **alignment**, **separation**: how hard each bird
  steers toward the middle of the birds it sees, along with their
  heading, and away from any closer than the separation radius.
- **… radius**: how far a bird looks for each.
- **view angle**: how wide a bird sees, centered on its heading: 180°
  only ahead, 360° all around.
- **clear view**, **back off**: steering around birds right ahead (in
  the blocker cone, closer than the blocker radius), sideways or
  straight back. Both are off at first.
- **min speed**, **max speed**: the limits on how fast a bird flies.
  Dragging one past the other pushes the other along.

The weights (cohesion, alignment, separation, clear view, back off) and
the count are useful over orders of magnitude, so their sliders go as a
cube: halfway along is an eighth of the way up. R, D and S change the
rules or the flock, and the sliders follow. H hides the rules, and the
flock takes their room.

Boids.lean can be changed while the flock flies: open it in the editor,
change it, and press Ctrl+R. Every Boids window starts again with the
new code ([Reloading an app](reloading.md),
[Change Boids while it flies](../explore/boids-live.md)). The
simulation, in Apps/Boids/, is built into the desktop and can't be
reloaded.

[↑ Use](README.md)
