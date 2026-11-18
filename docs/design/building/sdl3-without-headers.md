# SDL3 without headers

`shim.c` declares the twelve SDL calls it
uses and reads event fields at the offsets Schevana v0 reads: a key's
code at 28 and modifiers at 32, a text event's string at 24.

[↑ Building and linking](README.md)
