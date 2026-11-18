# Text out of the shim

SDL sends text only after
`SDL_StartTextInput(window)`, as a pointer to a string it frees at the
next poll. `Host.event` returns a `RawEvent`, a structure of a
`FloatArray` and a `String`; Lean lays out a structure of two boxed
fields as a plain two-field constructor, so C builds it with
`lean_alloc_ctor(0, 2, 0)` and copies the text into it. One call per
event, and no text waiting in a C global.

[↑ Drawing and input](README.md)
