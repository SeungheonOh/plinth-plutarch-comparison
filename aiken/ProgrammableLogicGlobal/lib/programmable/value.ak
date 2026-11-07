//// Merge-based helpers over ledger values. Ledger values are ordered by
//// policy id and asset name, which lets every operation here walk both sides
//// once. Quantities are kept as-is (including zero sums).

use aiken/builtin
use aiken/collection/dict
use aiken/collection/pairs
use cardano/assets.{AssetName, Assets, PolicyId, Tokens}

/// Policy-indexed asset bundles, in ascending policy order.
pub type Bundle =
  Pairs<PolicyId, Tokens>

/// Token quantities of a single policy, in ascending asset-name order.
pub type TokenList =
  Pairs<AssetName, Int>

/// Every entry but the first one, which in a ledger output value is Ada.
pub fn strip_ada(value: Assets) -> Bundle {
  when assets.to_pairs(value) is {
    [] -> []
    [_, ..rest] -> rest
  }
}

/// The first non-Ada policy of a ledger value is `policy`.
pub fn has_policy_first_non_ada(value: Assets, policy: PolicyId) -> Bool {
  when assets.to_pairs(value) is {
    [_, Pair(second, _), ..] -> second == policy
    _ -> False
  }
}

/// Asset-wise sum of two bundles.
pub fn union(left: Bundle, right: Bundle) -> Bundle {
  when left is {
    [] -> right
    [Pair(lk, lv) as l, ..left_rest] ->
      when right is {
        [] -> left
        [Pair(rk, rv) as r, ..right_rest] ->
          if lk == rk {
            [
              Pair(
                lk,
                dict.union_with(
                  lv,
                  rv,
                  fn(_, a, b, keep, _discard) { keep(a + b) },
                ),
              ),
              ..union(left_rest, right_rest)
            ]
          } else if builtin.less_than_bytearray(lk, rk) {
            [l, ..union(left_rest, right)]
          } else {
            [r, ..union(left, right_rest)]
          }
      }
  }
}

/// Quantity of an asset in a bundle (0 when absent).
pub fn bundle_quantity_of(
  bundle: Bundle,
  policy: PolicyId,
  name: AssetName,
) -> Int {
  when pairs.get_first(bundle, policy) is {
    None -> 0
    Some(tokens) ->
      when pairs.get_first(dict.to_pairs(tokens), name) is {
        None -> 0
        Some(quantity) -> quantity
      }
  }
}

/// Asset-wise sum of two token lists.
pub fn tokens_union(left: TokenList, right: TokenList) -> TokenList {
  when left is {
    [] -> right
    [Pair(lk, lq) as l, ..left_rest] ->
      when right is {
        [] -> left
        [Pair(rk, rq) as r, ..right_rest] ->
          if lk == rk {
            [Pair(lk, lq + rq), ..tokens_union(left_rest, right_rest)]
          } else if builtin.less_than_bytearray(lk, rk) {
            [l, ..tokens_union(left_rest, right)]
          } else {
            [r, ..tokens_union(left, right_rest)]
          }
      }
  }
}

fn tokens_negate(tokens: TokenList) -> TokenList {
  when tokens is {
    [] -> []
    [Pair(k, q), ..rest] -> [Pair(k, -q), ..tokens_negate(rest)]
  }
}

/// `inputs - outputs`, asset-wise; assets present on both sides whose
/// difference is zero are dropped.
pub fn tokens_subtract(inputs: TokenList, outputs: TokenList) -> TokenList {
  when inputs is {
    [] -> tokens_negate(outputs)
    [Pair(ik, iq) as i, ..inputs_rest] ->
      when outputs is {
        [] -> inputs
        [Pair(ok, oq), ..outputs_rest] ->
          if builtin.less_than_bytearray(ik, ok) {
            [i, ..tokens_subtract(inputs_rest, outputs)]
          } else if ik == ok {
            let diff = iq - oq
            if diff == 0 {
              tokens_subtract(inputs_rest, outputs_rest)
            } else {
              [Pair(ik, diff), ..tokens_subtract(inputs_rest, outputs_rest)]
            }
          } else {
            [Pair(ok, -oq), ..tokens_subtract(inputs, outputs_rest)]
          }
      }
  }
}

/// `actual` holds at least `required` of every asset (absent counts as 0).
pub fn tokens_contain(actual: TokenList, required: TokenList) -> Bool {
  when required is {
    [] -> True
    [Pair(rk, rq), ..required_rest] ->
      when actual is {
        [] -> 0 >= rq && tokens_contain([], required_rest)
        [Pair(ak, aq), ..actual_rest] ->
          if ak == rk {
            aq >= rq && tokens_contain(actual_rest, required_rest)
          } else if builtin.less_than_bytearray(ak, rk) {
            tokens_contain(actual_rest, required)
          } else {
            0 >= rq && tokens_contain(actual, required_rest)
          }
      }
  }
}
