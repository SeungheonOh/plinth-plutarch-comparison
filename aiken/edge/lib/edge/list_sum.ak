use aiken/collection/list

/// Sum of a list of integers.
pub fn list_sum(values: List<Int>) -> Int {
  list.foldl(values, 0, fn(value, total) { total + value })
}
