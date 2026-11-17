/-! # Pictures: what the view makes and the host draws, as plain data -/

namespace LeanMachine

inductive Picture where
  | rect (x y w h radius : Float) (rgb : UInt32)
  | text (x y size : Float) (rgb : UInt32) (s : String)
  | group (ps : List Picture)

end LeanMachine
