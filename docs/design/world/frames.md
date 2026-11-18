# An app says from its state whether it animates

An app that moves on its own, like Boids, needs frames: steady, 60 a
second, with a clock finer than a tick's seconds. Between events the
loop otherwise sleeps up to 100 ms, and then drawing costs nothing.

So an app says whether it wants frames, as a value of its state:
`App.animating`, from `App.asking`'s `animating`, the way the title
comes from `titleOf`. It isn't a request. A request is used up, and the
worlds undo keeps have empty outboxes, so an app that undo brought back
would stop. A flag computed from the state comes back with the state.

While a window that isn't minimized holds an app that animates
(`World.animating`), the loop waits no longer than the next frame. It
gives those apps `AppEvent.frame ms` before it draws. A minimized
window's app hears no frames: it is paused, the way browsers pause tabs
that aren't shown, and costs nothing.

Frames keep time. Each one is due a period (1/60 s) after the last was
due, not after it was drawn, so the work in a pass doesn't slow them.
If the loop falls a whole period behind, it starts again from now
rather than drawing the frames it missed all at once
(`nextFrameAfter`). Input still wakes the loop between frames, but a
frame comes only when it is due. So an app that steps once a frame goes
at the same speed whether the pointer moves or not. Schevana's Boids
checked the clock itself for this (`boids-step-ms`). A frame makes no
step that undo returns to.

A frame's time is a monotonic clock's milliseconds, not the time of
day. It never jumps back, so an app can tell how long it has been since
the last frame.

Headless (`SDL_VIDEO_DRIVER=dummy`), with a spinner on the start
desktop, 300 passes of the loop took 4,977 ms: 299 periods of 16.67 ms.

[↑ The world and apps](README.md)
