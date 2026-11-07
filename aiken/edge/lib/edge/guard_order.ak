use aiken/collection/list

/// The sum of `values`, provided `flag` is 1; fails otherwise.
pub fn guard_order(values: List<Int>, flag: Int) -> Int {
  let total = list.foldl(values, 0, fn(value, sum) { sum + value })
  if flag == 1 {
    total
  } else {
    fail
  }
}
