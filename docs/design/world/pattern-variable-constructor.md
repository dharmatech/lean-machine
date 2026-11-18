# A pattern variable can be a constructor

In `match o with | .read
text => …`, written inside `namespace Event`, `text` was taken for the
constructor `Event.text`, and Lean said "Not enough arguments to
`text`": a name in a pattern is a variable only if no constructor of
that name is in scope. Apps have many constructors in scope
(`Picture.text`, `AppEvent.text`, `Event.text`), so pattern
variables want names that aren't theirs.

[↑ The world and apps](README.md)
