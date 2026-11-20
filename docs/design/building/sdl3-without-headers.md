# SDL3 without headers

`shim.c` declares the fifteen SDL calls it
uses and reads event fields at the offsets Schevana v0 reads: a key's
code at 28 and modifiers at 32, a text event's string at 24, a mouse
button's number at 24 and how many clicks in a row it makes at 26, and
a resized window's width and height at 20 and 24. Those last two, and
the resized event's number, `0x206`, were checked against the
installed SDL3 with a few lines of C ([A resized window draws on a new
canvas](../drawing/new-canvas.md)).

[↑ Building and linking](README.md)
