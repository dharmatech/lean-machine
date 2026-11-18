# Monospace on Lean's grid

A pure view can't ask Cairo how wide text
is. For monospace text it doesn't have to: Lean fixes the advance at
0.6 em and the shim places glyph i at x + i·advance with
`cairo_show_glyphs` (Cairo's toy text API makes one glyph per
character). The font picked for "Monospace" here, DejaVu Sans Mono,
measures 0.602 em, so glyphs sit in their cells with no visible drift,
and a cursor or a click maps to a column by arithmetic.

[↑ Drawing and input](README.md)
