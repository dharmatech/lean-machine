# At 1000 boids, drawing costs more than the step

`--test` times a frame of the desktop with Boids open, back to back:

| boids | the step (a frame heard) | the desktop's view | drawn |
|------:|-------------------------:|-------------------:|------:|
|   150 |                  0.27 ms |            0.05 ms | 3.2 ms |
|  1000 |                  9.5 ms  |            0.09 ms | 12.1 ms |

Each boid is a line and a dot, and the renderer walks the `Picture`
and calls Cairo once for each. Every line is stroked and every dot
filled as a path of its own, about 5 µs each, so 2000 of them take
longer than the simulation that moved them. The desktop alone draws in
about 1.6 ms. Building the picture (the view) costs almost nothing.

Together, 1000 boids take about 22 ms a frame: some 46 frames a second
back to back, and fewer in the loop
([A frame costs more when frames are apart](../drawing/frames-apart.md)).
By these times, a frame's work passes a sixtieth of a second somewhere
around 800 boids.

Drawing all the lines of one colour as one path, with one stroke, and
all the dots as one fill, would cut most of that. That would mean a
`Picture` of many segments or many dots, which the renderer hands to
Cairo at once.

[↑ Boids](README.md)
