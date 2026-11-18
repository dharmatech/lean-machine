# Lists over arrays in app state

An app's state lives on in the
worlds undo keeps, so an `Array` push there copies the whole array
whenever an earlier world still holds it (Lean updates an array in
place only when nothing else holds it). The REPL's
transcript and history are lists, newest first: adding is a cons that
shares the rest with every earlier world.

[↑ The world and apps](README.md)
