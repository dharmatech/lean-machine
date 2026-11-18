# Frames a second, not ms a step

Schevana's Boids put a step's time in its status line ("4.0 ms a
step"), timed around the step. A Lean Machine app is pure and can't
read a clock, so it can't time its own step.

It does see the frames' times, which the loop gives it. So the status
line shows frames a second: the gaps between frames, smoothed over
about 20, as Schevana smoothed its step's time. A gap of more than a
quarter second, after a pause or while minimized, isn't counted.

Up to 60, the number says nothing about what a step costs. Only once a
step and drawing take longer than a frame does it drop. `--bench` and
`--test` time the step itself ([How fast a step is](step-speed.md)).

[↑ Boids](README.md)
