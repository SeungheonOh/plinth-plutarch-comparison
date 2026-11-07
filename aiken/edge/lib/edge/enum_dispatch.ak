pub type Op {
  Add(Int, Int)
  Sub(Int, Int)
  Mul(Int, Int)
  Neg(Int)
  MulAdd(Int, Int, Int)
  Div(Int, Int)
  Mod(Int, Int)
  Clamp(Int, Int, Int)
}

/// Evaluate one arithmetic operation.
pub fn enum_dispatch(op: Op) -> Int {
  when op is {
    Add(a, b) -> a + b
    Sub(a, b) -> a - b
    Mul(a, b) -> a * b
    Neg(a) -> -a
    MulAdd(a, b, c) -> a * b + c
    Div(a, b) -> a / b
    Mod(a, b) -> a % b
    Clamp(x, low, high) ->
      if x < low {
        low
      } else if x > high {
        high
      } else {
        x
      }
  }
}
