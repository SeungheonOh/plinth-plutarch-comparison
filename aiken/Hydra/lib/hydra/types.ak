use aiken/crypto.{VerificationKeyHash}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference}

pub type Hash =
  ByteArray

pub type Signature =
  ByteArray

pub type Commit {
  input: OutputReference,
  pre_serialized_output: ByteArray,
}

/// Open head state (the head seed is checked when decoding but not kept).
pub type OpenDatum {
  head_id: PolicyId,
  parties: List<ByteArray>,
  contestation_period: Int,
  version: Int,
  utxo_hash: Hash,
}

pub type ClosedDatum {
  head_id: PolicyId,
  parties: List<ByteArray>,
  contestation_period: Int,
  version: Int,
  snapshot_number: Int,
  utxo_hash: Hash,
  alpha_utxo_hash: Hash,
  omega_utxo_hash: Hash,
  contesters: List<VerificationKeyHash>,
  contestation_deadline: Int,
}

pub type State {
  Open(OpenDatum)
  Closed(ClosedDatum)
  Final
}

pub type CloseRedeemer {
  CloseInitial
  CloseAny { signature: List<Signature> }
  CloseUnusedDec { signature: List<Signature> }
  CloseUsedDec { signature: List<Signature>, already_decommitted: Hash }
  CloseUnusedInc { signature: List<Signature>, already_committed: Hash }
  CloseUsedInc { signature: List<Signature>, already_committed: Hash }
}

pub type ContestRedeemer {
  ContestCurrent { signature: List<Signature> }
  ContestUsedDec { signature: List<Signature>, already_decommitted: Hash }
  ContestUnusedDec { signature: List<Signature> }
  ContestUnusedInc { signature: List<Signature>, already_committed: Hash }
  ContestUsedInc { signature: List<Signature> }
}

pub type IncrementRedeemer {
  signature: List<Signature>,
  snapshot_number: Int,
  increment_ref: OutputReference,
}

pub type DecrementRedeemer {
  signature: List<Signature>,
  snapshot_number: Int,
  number_of_decommit_outputs: Int,
}

pub type HeadInput {
  CollectCom
  Increment(IncrementRedeemer)
  Decrement(DecrementRedeemer)
  Close(CloseRedeemer)
  Contest(ContestRedeemer)
  Abort
  Fanout {
    number_of_fanout_outputs: Int,
    number_of_commit_outputs: Int,
    number_of_decommit_outputs: Int,
  }
}
