# Colours on the grid

`Picture` needed nothing new: the grid says
where every character goes, so a row of several colours is a `mono`
for each run of one colour, at the column it starts in. A REPL window
full of highlighted lines draws 156 monos instead of 24, in 375 µs
instead of 200 (about 1.3 µs a mono: Cairo selects the font, turns
text into glyphs and composites, per call), and makes its view in 80
µs instead of 37. A frame still takes about 1.6 ms. A `mono` with a
colour for each character, one call into the shim a row, would save
most of that if many windows showed code.

[↑ Drawing and input](README.md)
