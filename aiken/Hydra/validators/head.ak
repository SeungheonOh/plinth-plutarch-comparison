use aiken/builtin
use aiken/cbor
use aiken/collection/list
use aiken/crypto.{VerificationKeyHash, sha2_256}
use aiken/interval.{Finite}
use aiken/primitive/bytearray
use cardano/assets.{PolicyId}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use cardano/transaction/output_reference
use hydra/decode
use hydra/types.{
  Close, CloseAny, CloseInitial, CloseRedeemer, CloseUnusedDec, CloseUnusedInc,
  CloseUsedDec, CloseUsedInc, Closed, ClosedDatum, Commit, Contest,
  ContestCurrent, ContestRedeemer, ContestUnusedDec, ContestUnusedInc,
  ContestUsedDec, ContestUsedInc, Decrement, DecrementRedeemer, Fanout, Hash,
  Increment, IncrementRedeemer, Open, OpenDatum, Signature,
}
use hydra/value

const hydra_head_v2: ByteArray = "HydraHeadV2"

/// sha2_256 of the empty byte string, i.e. the hash of no outputs.
const empty_hash: Hash =
  #"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

validator head {
  spend(
    datum: Option<Data>,
    redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(datum) = datum
    let state = decode.state(datum)
    let redeemer = decode.head_input(redeemer)
    when state is {
      Open(open) ->
        when redeemer is {
          Increment(r) -> check_increment(own_ref, self, open, r)
          Decrement(r) -> check_decrement(own_ref, self, open, r)
          Close(r) -> check_close(own_ref, self, open, r)
          _ -> fail
        }
      Closed(closed) ->
        when redeemer is {
          Contest(r) -> check_contest(own_ref, self, closed, r)
          Fanout {
            number_of_fanout_outputs,
            number_of_commit_outputs,
            number_of_decommit_outputs,
          } ->
            check_fanout(
              self,
              closed,
              number_of_fanout_outputs,
              number_of_commit_outputs,
              number_of_decommit_outputs,
            )
          _ -> fail
        }
      _ -> fail
    }
  }

  else(_) {
    fail
  }
}

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

fn hash_tx_outs(outputs: List<Output>) -> Hash {
  outputs
    |> list.foldr(
        #"",
        fn(output, acc) { bytearray.concat(cbor.serialise(output), acc) },
      )
    |> sha2_256
}

fn hash_pre_serialized_commits(commits: List<Commit>) -> Hash {
  commits
    |> list.sort(fn(a, b) { output_reference.compare(a.input, b.input) })
    |> list.foldr(
        #"",
        fn(commit, acc) { bytearray.concat(commit.pre_serialized_output, acc) },
      )
    |> sha2_256
}

fn deposit_commits(output: Output) -> List<Commit> {
  when output.datum is {
    InlineDatum(datum) -> decode.deposit_commits(datum)
    _ -> []
  }
}

fn has_st(head_id: PolicyId, output: Output) -> Bool {
  value.quantity_of(output.value, head_id, hydra_head_v2) == 1
}

fn must_be_signed_by_participant(
  signatories: List<VerificationKeyHash>,
  inputs: List<Input>,
  head_id: PolicyId,
) -> Bool {
  expect [signer] = signatories
  and {
    signer != hydra_head_v2,
    list.any(
      inputs,
      fn(input) { value.quantity_of(input.output.value, head_id, signer) == 1 },
    ),
  }
}

fn verify_snapshot_signature(
  parties: List<ByteArray>,
  head_id: PolicyId,
  version: Int,
  snapshot_number: Int,
  utxo_hash: Hash,
  utxo_to_commit_hash: Hash,
  utxo_to_decommit_hash: Hash,
  signatures: List<Signature>,
) -> Bool {
  let message = cbor.serialise(head_id)
    |> bytearray.concat(cbor.serialise(version))
    |> bytearray.concat(cbor.serialise(snapshot_number))
    |> bytearray.concat(cbor.serialise(utxo_hash))
    |> bytearray.concat(cbor.serialise(utxo_to_commit_hash))
    |> bytearray.concat(cbor.serialise(utxo_to_decommit_hash))
  verify_all(parties, signatures, message)
}

fn verify_all(
  parties: List<ByteArray>,
  signatures: List<Signature>,
  message: ByteArray,
) -> Bool {
  when parties is {
    [] -> signatures == []
    [party, ..parties] ->
      when signatures is {
        [] -> False
        [signature, ..signatures] ->
          builtin.verify_ed25519_signature(party, message, signature) && verify_all(
            parties,
            signatures,
            message,
          )
      }
  }
}

/// The spent head input, the head output (first output, which must sit at the
/// head address) and that output's inline datum.
fn head_output(
  own_ref: OutputReference,
  inputs: List<Input>,
  outputs: List<Output>,
) -> (Output, Output, Data) {
  expect Some(own_input) = list.find(
    inputs,
    fn(input) { input.output_reference == own_ref },
  )
  expect [head_out, ..] = outputs
  expect head_out.address == own_input.output.address
  expect InlineDatum(datum) = head_out.datum
  (own_input.output, head_out, datum)
}

// ----------------------------------------------------------------------------
// Increment
// ----------------------------------------------------------------------------

fn check_increment(
  own_ref: OutputReference,
  tx: Transaction,
  open: OpenDatum,
  redeemer: IncrementRedeemer,
) -> Bool {
  let Transaction { inputs, outputs, extra_signatories, .. } = tx
  let (_, head_out, datum) = head_output(own_ref, inputs, outputs)
  expect Open(next) = decode.state(datum)
  let IncrementRedeemer { signature, snapshot_number, increment_ref } = redeemer
  expect Some(deposit_input) = list.find(
    inputs,
    fn(input) { input.output_reference == increment_ref },
  )
  expect Some(head_input) = list.find(
    inputs,
    fn(input) { has_st(open.head_id, input.output) },
  )
  and {
    next.parties == open.parties,
    next.contestation_period == open.contestation_period,
    next.head_id == open.head_id,
    next.version == open.version + 1,
    value.sum_equals(
      [head_input.output.value, deposit_input.output.value],
      head_out.value,
    ),
    must_be_signed_by_participant(extra_signatories, inputs, open.head_id),
    verify_snapshot_signature(
      next.parties,
      next.head_id,
      open.version,
      snapshot_number,
      next.utxo_hash,
      hash_pre_serialized_commits(deposit_commits(deposit_input.output)),
      empty_hash,
      signature,
    ),
    list.any(inputs, fn(input) { input.output_reference == increment_ref }),
  }
}

// ----------------------------------------------------------------------------
// Decrement
// ----------------------------------------------------------------------------

fn check_decrement(
  own_ref: OutputReference,
  tx: Transaction,
  open: OpenDatum,
  redeemer: DecrementRedeemer,
) -> Bool {
  let Transaction { inputs, outputs, extra_signatories, .. } = tx
  let (own_output, head_out, datum) = head_output(own_ref, inputs, outputs)
  expect Open(next) = decode.state(datum)
  let  
      DecrementRedeemer {
        signature,
        snapshot_number,
        number_of_decommit_outputs,
      }
    = redeemer
  expect [_, ..rest_outputs] = outputs
  let decommit_outputs = list.take(rest_outputs, number_of_decommit_outputs)
  and {
    next.parties == open.parties,
    next.contestation_period == open.contestation_period,
    next.head_id == open.head_id,
    next.version == open.version + 1,
    verify_snapshot_signature(
      next.parties,
      next.head_id,
      open.version,
      snapshot_number,
      next.utxo_hash,
      empty_hash,
      hash_tx_outs(decommit_outputs),
      signature,
    ),
    value.sum_equals(
      [
        head_out.value,
        ..list.map(decommit_outputs, fn(output) { output.value })
      ],
      own_output.value,
    ),
    must_be_signed_by_participant(extra_signatories, inputs, open.head_id),
  }
}

// ----------------------------------------------------------------------------
// Close
// ----------------------------------------------------------------------------

fn check_close(
  own_ref: OutputReference,
  tx: Transaction,
  open: OpenDatum,
  redeemer: CloseRedeemer,
) -> Bool {
  let  
      Transaction {
        inputs,
        outputs,
        mint,
        validity_range,
        extra_signatories,
        ..
      }
    = tx
  let (own_output, head_out, datum) = head_output(own_ref, inputs, outputs)
  expect Closed(closed) = decode.state(datum)
  let OpenDatum { head_id, parties, contestation_period, version, utxo_hash } = open
  expect Finite(t_max) = validity_range.upper_bound.bound_type
  expect Finite(t_min) = validity_range.lower_bound.bound_type
  and {
    assets.is_zero(mint),
    t_max - t_min <= contestation_period,
    closed.contestation_deadline == t_max + contestation_period,
    must_be_signed_by_participant(extra_signatories, inputs, head_id),
    closed.version == version,
    when redeemer is {
      CloseInitial -> and {
          version == 0,
          closed.snapshot_number == 0,
          closed.utxo_hash == utxo_hash,
        }
      CloseAny { signature } -> and {
          closed.snapshot_number > 0,
          closed.alpha_utxo_hash == empty_hash,
          closed.omega_utxo_hash == empty_hash,
          verify_snapshot_signature(
            parties,
            head_id,
            version,
            closed.snapshot_number,
            closed.utxo_hash,
            empty_hash,
            empty_hash,
            signature,
          ),
        }
      CloseUnusedDec { signature } -> and {
          closed.alpha_utxo_hash == empty_hash,
          closed.omega_utxo_hash != empty_hash,
          verify_snapshot_signature(
            parties,
            head_id,
            version,
            closed.snapshot_number,
            closed.utxo_hash,
            empty_hash,
            closed.omega_utxo_hash,
            signature,
          ),
        }
      CloseUsedDec { signature, already_decommitted } -> and {
          closed.alpha_utxo_hash == empty_hash,
          closed.omega_utxo_hash == empty_hash,
          verify_snapshot_signature(
            parties,
            head_id,
            version - 1,
            closed.snapshot_number,
            closed.utxo_hash,
            empty_hash,
            already_decommitted,
            signature,
          ),
        }
      CloseUnusedInc { signature, already_committed } -> and {
          closed.alpha_utxo_hash == empty_hash,
          closed.omega_utxo_hash == empty_hash,
          verify_snapshot_signature(
            parties,
            head_id,
            version,
            closed.snapshot_number,
            closed.utxo_hash,
            already_committed,
            empty_hash,
            signature,
          ),
        }
      CloseUsedInc { signature, already_committed } -> and {
          closed.alpha_utxo_hash == already_committed,
          closed.omega_utxo_hash == empty_hash,
          verify_snapshot_signature(
            parties,
            head_id,
            version - 1,
            closed.snapshot_number,
            closed.utxo_hash,
            already_committed,
            empty_hash,
            signature,
          ),
        }
    },
    closed.contesters == [],
    value.geq(head_out.value, own_output.value),
    closed.parties == parties,
    closed.contestation_period == contestation_period,
    closed.head_id == head_id,
  }
}

// ----------------------------------------------------------------------------
// Contest
// ----------------------------------------------------------------------------

fn check_contest(
  own_ref: OutputReference,
  tx: Transaction,
  closed: ClosedDatum,
  redeemer: ContestRedeemer,
) -> Bool {
  let  
      Transaction {
        inputs,
        outputs,
        mint,
        validity_range,
        extra_signatories,
        ..
      }
    = tx
  let (own_output, head_out, datum) = head_output(own_ref, inputs, outputs)
  expect Closed(next) = decode.state(datum)
  let  
      ClosedDatum {
        head_id,
        parties,
        contestation_period,
        version,
        snapshot_number,
        contesters,
        contestation_deadline,
        ..
      }
    = closed
  expect [contester] = extra_signatories
  and {
    assets.is_zero(mint),
    next.version == version,
    next.snapshot_number > snapshot_number,
    when redeemer is {
      ContestCurrent { signature } -> and {
          next.alpha_utxo_hash == empty_hash,
          next.omega_utxo_hash == empty_hash,
          verify_snapshot_signature(
            parties,
            head_id,
            version,
            next.snapshot_number,
            next.utxo_hash,
            empty_hash,
            empty_hash,
            signature,
          ),
        }
      ContestUsedDec { signature, already_decommitted } -> and {
          next.alpha_utxo_hash == empty_hash,
          next.omega_utxo_hash == empty_hash,
          verify_snapshot_signature(
            parties,
            head_id,
            version - 1,
            next.snapshot_number,
            next.utxo_hash,
            empty_hash,
            already_decommitted,
            signature,
          ),
        }
      ContestUnusedDec { signature } -> and {
          next.alpha_utxo_hash == empty_hash,
          verify_snapshot_signature(
            parties,
            head_id,
            version,
            next.snapshot_number,
            next.utxo_hash,
            empty_hash,
            next.omega_utxo_hash,
            signature,
          ),
        }
      ContestUnusedInc { signature, already_committed } -> and {
          next.omega_utxo_hash == empty_hash,
          verify_snapshot_signature(
            parties,
            head_id,
            version - 1,
            next.snapshot_number,
            next.utxo_hash,
            already_committed,
            empty_hash,
            signature,
          ),
        }
      ContestUsedInc { signature } -> and {
          next.omega_utxo_hash == empty_hash,
          verify_snapshot_signature(
            parties,
            head_id,
            version,
            next.snapshot_number,
            next.utxo_hash,
            next.alpha_utxo_hash,
            empty_hash,
            signature,
          ),
        }
    },
    must_be_signed_by_participant(extra_signatories, inputs, head_id),
    !list.has(contesters, contester),
    when validity_range.upper_bound.bound_type is {
      Finite(time) -> time <= contestation_deadline
      _ -> fail
    },
    next.contesters == [contester, ..contesters],
    if list.length(next.contesters) == list.length(parties) {
      next.contestation_deadline == contestation_deadline
    } else {
      next.contestation_deadline == contestation_deadline + contestation_period
    },
    next.parties == parties,
    next.contestation_period == contestation_period,
    next.head_id == head_id,
    value.geq(head_out.value, own_output.value),
  }
}

// ----------------------------------------------------------------------------
// Fanout
// ----------------------------------------------------------------------------

fn check_fanout(
  tx: Transaction,
  closed: ClosedDatum,
  number_of_fanout_outputs: Int,
  number_of_commit_outputs: Int,
  number_of_decommit_outputs: Int,
) -> Bool {
  let Transaction { mint, outputs, validity_range, .. } = tx
  let after_fanout = list.drop(outputs, number_of_fanout_outputs)
  and {
    -value.policy_total(mint, closed.head_id) == list.length(closed.parties) + 1,
    hash_tx_outs(list.take(outputs, number_of_fanout_outputs)) == closed.utxo_hash,
    closed.alpha_utxo_hash == hash_tx_outs(
      list.take(after_fanout, number_of_commit_outputs),
    ),
    closed.omega_utxo_hash == hash_tx_outs(
      list.take(after_fanout, number_of_decommit_outputs),
    ),
    when validity_range.lower_bound.bound_type is {
      Finite(time) -> time > closed.contestation_deadline
      _ -> fail
    },
  }
}
