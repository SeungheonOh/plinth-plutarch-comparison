use aiken/collection/list
use cardano/assets.{AssetName, PolicyId}
use cardano/governance.{Voter}
use cardano/transaction.{Input, Transaction}

/// Voting is authorised when any transaction input carries exactly one unit of
/// the configured voting token.
validator voting(policy_id: PolicyId, asset_name: AssetName) {
  vote(_redeemer: Data, _voter: Voter, self: Transaction) {
    list.any(
      self.inputs,
      fn(input: Input) {
        assets.quantity_of(input.output.value, policy_id, asset_name) == 1
      },
    )
  }

  else(_) {
    fail
  }
}
