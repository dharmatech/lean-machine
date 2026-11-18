# The taskbar guesses how wide text is

A view can center text without knowing its width: `Picture.textIn`
puts text in a box, and Cairo measures it in the shim as it draws, so
the view stays pure. The taskbar needs more. Its hint gives way when
the buttons would be too narrow for their titles, and the world, not
the view, decides where the buttons are, since a press has to find
them where they're drawn. The world is pure Lean, with no Cairo to ask.

So it guesses (`approxW`): 0.6 em a letter, monospace's advance
([Monospace on Lean's grid](monospace-grid.md)), which is wider than
most letters of the proportional font, and half that for a space. At
the bar's 13 pixels it guesses 540 pixels for the hint and the count,
where Cairo draws 440. The hint, right-aligned against the count, stays
clear of the buttons, but gives way a window or so early. A title too
long for its button is cut at the button's edge (`Picture.clip`), not
shortened with an ellipsis, which would also need its width.

Two ways to measure for real, and stay pure:

- The shim measures the advance of each character of the bar's font
  once, at the start, and the world keeps them as a table. Widths are
  then sums, with no kerning: near enough for a bar.
- A pure `@[extern]` that asks Cairo. Lean takes an extern's word that
  it's a function, so it must be one: the same font, every call.

Either would serve text that wraps too (Notes), which is waiting for
the same thing ([Ideas](../../ideas.md)).

[↑ Drawing and input](README.md)
