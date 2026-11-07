//// Decoding of user-supplied data (datums and redeemers) with the
//// specification's rules: constructor tags are checked, every field is
//// checked to have its declared shape (whether it is used or not), and
//// trailing extra fields are ignored.

use aiken/builtin
use aiken/collection/list
use cardano/transaction.{OutputReference}
use hydra/types.{
  Abort, Close, CloseAny, CloseInitial, CloseRedeemer, CloseUnusedDec,
  CloseUnusedInc, CloseUsedDec, CloseUsedInc, Closed, ClosedDatum, CollectCom,
  Commit, Contest, ContestCurrent, ContestRedeemer, ContestUnusedDec,
  ContestUnusedInc, ContestUsedDec, ContestUsedInc, Decrement, DecrementRedeemer,
  Fanout, Final, HeadInput, Increment, IncrementRedeemer, Open, OpenDatum, State,
}

// ----------------------------------------------------------------------------
// Shape checks
// ----------------------------------------------------------------------------

fn is_bytes(data: Data) -> Bool {
  builtin.choose_data(data, False, False, False, False, True)
}

fn is_int(data: Data) -> Bool {
  builtin.choose_data(data, False, False, False, True, False)
}

fn is_bytes_list(data: Data) -> Bool {
  builtin.choose_data(data, False, False, True, False, False) && list.all(
    builtin.un_list_data(data),
    is_bytes,
  )
}

/// Fields of `data` when it is a constructor with the given tag.
fn try_fields(data: Data, tag: Int) -> Option<List<Data>> {
  if builtin.choose_data(data, True, False, False, False, False) {
    let constr = builtin.un_constr_data(data)
    if constr.1st == tag {
      Some(constr.2nd)
    } else {
      None
    }
  } else {
    None
  }
}

fn is_output_reference(data: Data) -> Bool {
  when try_fields(data, 0) is {
    Some([transaction_id, output_index, ..]) ->
      is_bytes(transaction_id) && is_int(output_index)
    _ -> False
  }
}

// ----------------------------------------------------------------------------
// Conversions (applied once a field's shape has been checked)
// ----------------------------------------------------------------------------

fn bytes_list(data: Data) -> List<ByteArray> {
  expect xs: List<ByteArray> = data
  xs
}

fn output_reference(data: Data) -> OutputReference {
  expect [transaction_id, output_index, ..] = builtin.un_constr_data(data).2nd
  OutputReference {
    transaction_id: builtin.un_b_data(transaction_id),
    output_index: builtin.un_i_data(output_index),
  }
}

/// Fields of a constructor that must carry the given tag.
fn tagged_fields(data: Data, tag: Int) -> List<Data> {
  let constr = builtin.un_constr_data(data)
  expect constr.1st == tag
  constr.2nd
}

/// A signature list followed (when `with_hash`) by a hash.
fn signature_and_hash(
  fields: List<Data>,
  with_hash: Bool,
) -> (List<ByteArray>, ByteArray) {
  expect [signature, ..rest] = fields
  expect is_bytes_list(signature)
  if with_hash {
    expect [hash, ..] = rest
    expect is_bytes(hash)
    (bytes_list(signature), builtin.un_b_data(hash))
  } else {
    (bytes_list(signature), #"")
  }
}

// ----------------------------------------------------------------------------
// Datum
// ----------------------------------------------------------------------------

fn open_datum(data: Data) -> OpenDatum {
  expect  
      [head_seed, head_id, parties, contestation_period, version, utxo_hash, ..]
    = tagged_fields(data, 0)
  expect and {
      is_output_reference(head_seed),
      is_bytes(head_id),
      is_bytes_list(parties),
      is_int(contestation_period),
      is_int(version),
      is_bytes(utxo_hash),
    }
  OpenDatum {
    head_id: builtin.un_b_data(head_id),
    parties: bytes_list(parties),
    contestation_period: builtin.un_i_data(contestation_period),
    version: builtin.un_i_data(version),
    utxo_hash: builtin.un_b_data(utxo_hash),
  }
}

fn closed_datum(data: Data) -> ClosedDatum {
  expect  
      [
        head_id, parties, contestation_period, version, snapshot_number,
        utxo_hash, alpha_utxo_hash, omega_utxo_hash, contesters,
        contestation_deadline,
        ..
      ]
    = tagged_fields(data, 0)
  expect and {
      is_bytes(head_id),
      is_bytes_list(parties),
      is_int(contestation_period),
      is_int(version),
      is_int(snapshot_number),
      is_bytes(utxo_hash),
      is_bytes(alpha_utxo_hash),
      is_bytes(omega_utxo_hash),
      is_bytes_list(contesters),
      is_int(contestation_deadline),
    }
  ClosedDatum {
    head_id: builtin.un_b_data(head_id),
    parties: bytes_list(parties),
    contestation_period: builtin.un_i_data(contestation_period),
    version: builtin.un_i_data(version),
    snapshot_number: builtin.un_i_data(snapshot_number),
    utxo_hash: builtin.un_b_data(utxo_hash),
    alpha_utxo_hash: builtin.un_b_data(alpha_utxo_hash),
    omega_utxo_hash: builtin.un_b_data(omega_utxo_hash),
    contesters: bytes_list(contesters),
    contestation_deadline: builtin.un_i_data(contestation_deadline),
  }
}

pub fn state(data: Data) -> State {
  let constr = builtin.un_constr_data(data)
  when constr.1st is {
    0 -> {
      expect [open, ..] = constr.2nd
      Open(open_datum(open))
    }
    1 -> {
      expect [closed, ..] = constr.2nd
      Closed(closed_datum(closed))
    }
    2 -> Final
    _ -> fail
  }
}

// ----------------------------------------------------------------------------
// Redeemer
// ----------------------------------------------------------------------------

fn close_redeemer(data: Data) -> CloseRedeemer {
  let constr = builtin.un_constr_data(data)
  let fields = constr.2nd
  when constr.1st is {
    0 -> CloseInitial
    1 -> CloseAny { signature: signature_and_hash(fields, False).1st }
    2 -> CloseUnusedDec { signature: signature_and_hash(fields, False).1st }
    3 -> {
      let (signature, hash) = signature_and_hash(fields, True)
      CloseUsedDec { signature, already_decommitted: hash }
    }
    4 -> {
      let (signature, hash) = signature_and_hash(fields, True)
      CloseUnusedInc { signature, already_committed: hash }
    }
    5 -> {
      let (signature, hash) = signature_and_hash(fields, True)
      CloseUsedInc { signature, already_committed: hash }
    }
    _ -> fail
  }
}

fn contest_redeemer(data: Data) -> ContestRedeemer {
  let constr = builtin.un_constr_data(data)
  let fields = constr.2nd
  when constr.1st is {
    0 -> ContestCurrent { signature: signature_and_hash(fields, False).1st }
    1 -> {
      let (signature, hash) = signature_and_hash(fields, True)
      ContestUsedDec { signature, already_decommitted: hash }
    }
    2 -> ContestUnusedDec { signature: signature_and_hash(fields, False).1st }
    3 -> {
      let (signature, hash) = signature_and_hash(fields, True)
      ContestUnusedInc { signature, already_committed: hash }
    }
    4 -> ContestUsedInc { signature: signature_and_hash(fields, False).1st }
    _ -> fail
  }
}

pub fn head_input(data: Data) -> HeadInput {
  let constr = builtin.un_constr_data(data)
  let fields = constr.2nd
  when constr.1st is {
    0 -> CollectCom
    1 -> {
      expect [redeemer, ..] = fields
      expect [signature,
            snapshot_number, increment_ref, ..] = tagged_fields(redeemer, 0)
      expect and {
          is_bytes_list(signature),
          is_int(snapshot_number),
          is_output_reference(increment_ref),
        }
      Increment(
        IncrementRedeemer {
          signature: bytes_list(signature),
          snapshot_number: builtin.un_i_data(snapshot_number),
          increment_ref: output_reference(increment_ref),
        },
      )
    }
    2 -> {
      expect [redeemer, ..] = fields
      expect [signature,
            snapshot_number,
            number_of_decommit_outputs, ..] = tagged_fields(redeemer, 0)
      expect and {
          is_bytes_list(signature),
          is_int(snapshot_number),
          is_int(number_of_decommit_outputs),
        }
      Decrement(
        DecrementRedeemer {
          signature: bytes_list(signature),
          snapshot_number: builtin.un_i_data(snapshot_number),
          number_of_decommit_outputs: builtin.un_i_data(
            number_of_decommit_outputs,
          ),
        },
      )
    }
    3 -> {
      expect [redeemer, ..] = fields
      Close(close_redeemer(redeemer))
    }
    4 -> {
      expect [redeemer, ..] = fields
      Contest(contest_redeemer(redeemer))
    }
    5 -> Abort
    6 -> {
      expect [fanout, commit, decommit, ..] = fields
      expect and {
          is_int(fanout),
          is_int(commit),
          is_int(decommit),
        }
      Fanout {
        number_of_fanout_outputs: builtin.un_i_data(fanout),
        number_of_commit_outputs: builtin.un_i_data(commit),
        number_of_decommit_outputs: builtin.un_i_data(decommit),
      }
    }
    _ -> fail
  }
}

// ----------------------------------------------------------------------------
// Deposit datum (optional: a malformed one counts as having no commits)
// ----------------------------------------------------------------------------

fn try_commits(items: List<Data>) -> Option<List<Commit>> {
  when items is {
    [] -> Some([])
    [item, ..rest] ->
      when try_fields(item, 0) is {
        Some([input, pre_serialized_output, ..]) ->
          if is_output_reference(input) && is_bytes(pre_serialized_output) {
            when try_commits(rest) is {
              None -> None
              Some(commits) ->
                Some(
                  [
                    Commit {
                      input: output_reference(input),
                      pre_serialized_output: builtin.un_b_data(
                        pre_serialized_output,
                      ),
                    },
                    ..commits
                  ],
                )
            }
          } else {
            None
          }
        _ -> None
      }
  }
}

/// Commits of a deposit datum `(head id, deadline, commits)`; none when the
/// datum does not have that shape.
pub fn deposit_commits(data: Data) -> List<Commit> {
  when try_fields(data, 0) is {
    Some([head_id, deadline, commits, ..]) ->
      if and {
        is_bytes(head_id),
        is_int(deadline),
        builtin.choose_data(commits, False, False, True, False, False),
      } {
        when try_commits(builtin.un_list_data(commits)) is {
          Some(commits) -> commits
          None -> []
        }
      } else {
        []
      }
    _ -> []
  }
}
