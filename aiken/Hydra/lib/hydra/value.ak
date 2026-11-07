//// Value helpers with association-list semantics: lookups take the first
//// matching key and comparisons do not depend on key order, matching the
//// on-chain `Value` operations the Hydra head is specified against.

use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use cardano/assets.{AssetName, Assets, PolicyId}

/// Quantity of the given asset (0 when absent).
pub fn quantity_of(value: Assets, policy: PolicyId, name: AssetName) -> Int {
  when pairs.get_first(assets.to_pairs(value), policy) is {
    None -> 0
    Some(tokens) ->
      when pairs.get_first(dict.to_pairs(tokens), name) is {
        None -> 0
        Some(quantity) -> quantity
      }
  }
}

/// Sum of all quantities held under the given policy.
pub fn policy_total(value: Assets, policy: PolicyId) -> Int {
  when pairs.get_first(assets.to_pairs(value), policy) is {
    None -> 0
    Some(tokens) ->
      dict.foldl(tokens, 0, fn(_, quantity, total) { total + quantity })
  }
}

fn all_assets(
  value: Assets,
  predicate: fn(PolicyId, AssetName, Int) -> Bool,
) -> Bool {
  list.all(
    assets.to_pairs(value),
    fn(Pair(policy, tokens)) {
      list.all(
        dict.to_pairs(tokens),
        fn(Pair(name, quantity)) { predicate(policy, name, quantity) },
      )
    },
  )
}

/// `left` holds at least as much of every asset as `right`.
pub fn geq(left: Assets, right: Assets) -> Bool {
  and {
    all_assets(
      right,
      fn(policy, name, quantity) { quantity_of(left, policy, name) >= quantity },
    ),
    all_assets(
      left,
      fn(policy, name, quantity) {
        quantity >= 0 || quantity_of(right, policy, name) <= quantity
      },
    ),
  }
}

/// The asset-wise sum of `parts` equals `total`.
pub fn sum_equals(parts: List<Assets>, total: Assets) -> Bool {
  let matches = fn(policy, name, _) {
    list.foldl(
      parts,
      0,
      fn(part, sum) { sum + quantity_of(part, policy, name) },
    ) == quantity_of(total, policy, name)
  }
  all_assets(total, matches) && list.all(
    parts,
    fn(part) { all_assets(part, matches) },
  )
}
