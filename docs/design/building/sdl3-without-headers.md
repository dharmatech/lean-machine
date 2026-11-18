# SDL3 without headers

`shim.c` declares the twelve SDL calls it
uses and reads event fields at the offsets Schevana v0 reads: a key's
code at 28 and modifiers at 32, a text event's string at 24, a mouse
button's number at 24 and how many clicks in a row it makes at 26.

[↑ Building and linking](README.md)
