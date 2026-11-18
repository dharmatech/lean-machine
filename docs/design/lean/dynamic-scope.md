# Dynamic scope by hand

Lean has no thread-local or dynamically
scoped values (Scheme's `parameterize`), so `world` and `launch` reach
their run through a C++ thread-local the guard sets. Code that starts
tasks of its own leaves the ambient, and the stop flag, behind.

[↑ Lean inside the desktop](README.md)
