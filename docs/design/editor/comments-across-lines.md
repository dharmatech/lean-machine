# Comments and strings across lines

Lean's tokenizer reads a
whole file as gladly as a line (`whitespace` skips comments across
line ends), but it can't start inside a comment or a string, and it
stops at its first error with no recovery, so a file read in one go
would turn red from its first stray character to its end. The editor
reads a line at a time, and carries from each line to the next where
it ended: in code, in a comment so many deep (they nest), or in a
string. What the line before left open is read to its end by hand,
and where the tokenizer gives up on a comment or string that doesn't
end on this line, the line ends inside it: about 40 lines of scanning
over characters. Raw strings (`r#"…"#`) that span lines aren't
carried.

[↑ The editor](README.md)
