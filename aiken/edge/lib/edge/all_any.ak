use aiken/collection/list

pub type Item {
  Item { low: Int, high: Int, tag: ByteArray }
}

/// 1 when every item has `low < high` and some item carries `target`, else 0.
pub fn all_any(items: List<Item>, target: ByteArray) -> Int {
  if list.all(items, fn(item) { item.low < item.high }) && list.any(
    items,
    fn(item) { item.tag == target },
  ) {
    1
  } else {
    0
  }
}
