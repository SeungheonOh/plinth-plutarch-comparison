use aiken/collection/list

/// Total length of the inner lists whose first element is even.
pub fn nested_lists(lists: List<List<Int>>) -> Int {
  list.foldl(
    lists,
    0,
    fn(inner, total) {
      when inner is {
        [first, ..] ->
          if first % 2 == 0 {
            total + list.length(inner)
          } else {
            total
          }
        [] -> total
      }
    },
  )
}
