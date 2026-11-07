use aiken/collection/list

/// Position of the first occurrence of `target`, or -1.
pub fn byte_search(keys: List<ByteArray>, target: ByteArray) -> Int {
  when list.index_of(keys, target) is {
    Some(index) -> index
    None -> -1
  }
}
