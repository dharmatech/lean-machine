# Highlighting by Lean's tokenizer

Lean's tokenizer
(`Lean.Parser.tokenFn`) reads one token at a time with the
environment's token table, so the REPL's own Lean decides what a token
is, and notation defined in a REPL is read as the parser will read
it. Each token comes back as syntax with its place in the line: an
atom (a keyword when it's a word, as Lean's editor decides: `def`,
`s!`, `#eval`; a symbol otherwise), an identifier, or a literal. A
line of 52 characters takes 22 µs, about a microsecond a token, and
one of 200 characters 97 µs; a keystroke, the REPL's step with the
line read again, 26 µs. Lean's whole parser takes 65 µs on the same
line, so parsing at every keystroke would be affordable too, but a
line being typed is seldom a whole term yet, and the parser's error
would turn the end of every unfinished line red.

[↑ Highlighting and completion](README.md)
