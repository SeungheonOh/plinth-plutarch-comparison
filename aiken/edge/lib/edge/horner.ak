use aiken/collection/list

/// Value at `x` of the polynomial whose coefficients are listed from the
/// highest degree down.
pub fn horner(coefficients: List<Int>, x: Int) -> Int {
  list.foldl(coefficients, 0, fn(coefficient, acc) { acc * x + coefficient })
}
