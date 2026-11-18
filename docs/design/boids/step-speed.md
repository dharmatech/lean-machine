# How fast a step is

`desktop --bench` times `Flock.stepOn` (a frame: a step, then the speed
limits and the wrap) on a field of 1200 × 700. It takes 10 steps, then
the mean of 30 more. The Chez column is Schevana's first port stepping
the same flock (see [The same bits as Chez](same-bits-as-chez.md)).
Both ran on one thread of an i9-10885H on 2026-11-17, in ms a step:

| boids | rules    | Chez   | Lean  | Chez ÷ Lean |
|------:|----------|-------:|------:|------------:|
|   150 | default  |   1.93 |  0.22 |         8.9 |
|   150 | heaviest |   4.53 |  0.71 |         6.4 |
|   300 | default  |   7.07 |  0.72 |         9.8 |
|   300 | heaviest |  14.63 |  2.18 |         6.7 |
|   500 | default  |  20.36 |  2.05 |         9.9 |
|   500 | heaviest |  39.10 |  5.80 |         6.7 |
|  1000 | default  |  76.84 |  7.78 |         9.9 |
|  1000 | heaviest | 157.32 | 22.79 |         6.9 |

The heaviest rules turn every rule on, as strong and as far-seeing as
the ranges go. Lean's numbers come from the desktop's own binary, so
every small allocation goes through runs.cpp's wrapper (a safepoint),
as it will in the app. Chez ran the file with `scheme --script` at its
default settings.

A frame at 60 Hz has 16.7 ms. In Lean, 1000 boids under the default
rules fit in one (7.8 ms), and under the heaviest rules about 500 do.
Schevana's port capped the flock at 450, where a step took about a
frame. The likely reasons for the gap:
- The loop that finds neighbors allocates nothing ([A vector made to be
  taken apart isn't made](vectors-not-made.md)).
- A `Vec` keeps its two doubles unboxed.
- The flock is an array, not a list.

None of these has been measured on its own.

In the window, the step isn't all of a frame: at 1000 boids, drawing
them costs more ([At 1000 boids, drawing costs more than the
step](drawing-costs-more.md)).

[↑ Boids](README.md)
