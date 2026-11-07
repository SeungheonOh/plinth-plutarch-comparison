use aiken/collection/list

/// How many values `x` have `2x + 1 > threshold`, written as a map, a filter
/// and a length.
pub fn map_filter_count(values: List<Int>, threshold: Int) -> Int {
  values
    |> list.map(fn(x) { 2 * x + 1 })
    |> list.filter(fn(y) { y > threshold })
    |> list.length
}
