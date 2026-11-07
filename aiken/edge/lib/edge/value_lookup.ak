use aiken/collection/pairs

/// Quantity of `token` under `policy` in a value-shaped nested map, or 0.
pub fn value_lookup(
  value: Pairs<ByteArray, Pairs<ByteArray, Int>>,
  policy: ByteArray,
  token: ByteArray,
) -> Int {
  when pairs.get_first(value, policy) is {
    None -> 0
    Some(tokens) ->
      when pairs.get_first(tokens, token) is {
        None -> 0
        Some(quantity) -> quantity
      }
  }
}
