# Requests in the world

Apps don't do I/O; they ask, and the world
keeps what they asked in an outbox, marked with the window, until the
loop takes it after each event. The outcome comes back as one more
event, to the window that asked. Results can't carry an `App`: an
`AppEvent` holding an `App` would put `App` to the left of an arrow in
its own definition (`step : AppEvent → …`), which Lean rejects as not
strictly positive. An app a REPL made goes to the world instead, as
`Event.launch`.

[↑ Runs, requests and threads](README.md)
