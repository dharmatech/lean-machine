# Time

Lean's `Std.Time` reads the local time (`PlainTime.now`) in
about 80 µs, time zone included, so the loop calls it every frame and
no C is needed. Time comes into the pure world only as events: a
tick with the time of day, and, for apps that animate, a frame with a
monotonic clock's milliseconds ([An app says from its state whether it
animates](frames.md)).
Undo puts back an earlier world, clocks included, but the loop ticks
before every frame, so a stale time is never drawn.

[↑ The world and apps](README.md)
