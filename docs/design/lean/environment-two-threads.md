# Reading an environment from two threads

The view calls the
tokenizer on the main thread while a run may be elaborating from the
same environment on another thread. Nothing needs a lock: the
environment is persistent data, and the run's closure marked it
multi-threaded when the run took it, so its reference counts change
atomically.

[↑ Lean inside the desktop](README.md)
