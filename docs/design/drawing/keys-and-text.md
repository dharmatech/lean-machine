# Keys and text are separate events

A key brings SDL's keycode and
modifiers; typing brings text, as the layout and any input method made
it ("é", "N"). Apps insert text and act on keys. Text typed with Ctrl
held is dropped (the shim sends the modifiers along with it), so
Ctrl+Shift+N doesn't also type an N. SDL may give a letter key in upper
case when Shift is down, so `Key.ofSDL` lowers it.

[↑ Drawing and input](README.md)
