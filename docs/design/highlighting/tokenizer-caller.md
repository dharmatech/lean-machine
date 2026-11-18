# What the tokenizer leaves to its caller

It isn't a lexer with an
API of its own: `tokenFn` is a `ParserFn`, run with an input context,
a module context (environment, options, namespace, open
declarations) and the token table (`ParserFn.run`), and the blanks
before the first token are skipped by hand (`whitespace`). Comments
aren't tokens: `whitespace` skips them after each token, so a comment
is whatever lies between tokens and isn't blank. Doc comments (`/--`,
`/-!`) are tokens whose bodies the tokenizer doesn't read
(`finishCommentBlock` does). It stops at the first error, with no
recovery, so the REPL colours the rest of the line red. Its
positions are bytes of UTF-8 (`String.Pos.Raw`) and the REPL's grid
counts characters, so each one is counted again (for nothing when the
line is ASCII).

[↑ Highlighting and completion](README.md)
