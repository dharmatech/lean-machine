# An app can't always return an app

`step : AppEvent → App` type
checks, but the type has no values: building one needs an `App`
already. `step` returns `Option (App × List Request)`, and `none` ends
the chain. An app that keeps state refers to itself, so it can't be
total; `App.asking` is the one `partial` definition, and apps passed
to it stay total.

[↑ The world and apps](README.md)
