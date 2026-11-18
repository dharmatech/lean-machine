# A frame costs more when frames are apart

The start desktop with a spinner (a line, turned by frames) takes
1.6 ms to draw and 0.7 ms to show (`Host.present`, SDL's dummy video
driver). Those times come from 100 frames drawn back to back.

In the loop at 60 frames a second, the same frame took 3.8 to 9.3 ms to
draw and show, and the process used about 40% of a core. The machine's
CPU runs the `powersave` governor (0.8 to 5.3 GHz), and a core that
sleeps for most of every 16.7 ms is slow when it wakes. The likely
cause is the clock rate, perhaps with cold caches; neither was measured
on its own.

So a frame's budget is less than 16.7 ms minus the back-to-back times.
A Boids step that `--bench` times at 7.8 ms may well take longer in the
loop. Drawing only what changed would help (the desktop redraws
everything every frame: [Speed](speed.md)).

[↑ Drawing and input](README.md)
