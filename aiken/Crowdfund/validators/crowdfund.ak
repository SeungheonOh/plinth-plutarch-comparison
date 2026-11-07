use aiken/builtin
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Finite, Interval}
use cardano/assets
use cardano/transaction.{InlineDatum, Output, OutputReference, Transaction}

// Datum:    CrowdfundDatum recipient goal deadline wallets   (Constr _ [B, I, I, Map])
// Redeemer: Donate amount donor | Withdraw | Reclaim           (Constr 0/1/2)
//
// Both are read straight from `Data`, the way the reference contract's
// `asData` accessors do: the constructor index of the (single-constructor)
// datum is not inspected, trailing fields are ignored, and only the parts
// that are used get decoded. Wallet keys are compared as `Data` and never
// decoded.

/// Fields of a value encoded as `Constr _ fields`, ignoring the index.
fn fields_of(data: Data) -> List<Data> {
  builtin.snd_pair(builtin.un_constr_data(data))
}

/// The validity range starts strictly before the deadline.
fn starts_before(range: Interval, deadline: Int) -> Bool {
  when range.lower_bound.bound_type is {
    Finite(t) -> t < deadline
    _ -> False
  }
}

/// Checks that the fields of a continuing output's datum carry the same
/// recipient, goal and deadline, and returns its wallets.
fn continuing_wallets(
  output: Output,
  recipient: VerificationKeyHash,
  goal: Int,
  deadline: Int,
) -> Option<Pairs<Data, Data>> {
  expect InlineDatum(datum) = output.datum
  expect [out_recipient,
        out_goal, out_deadline, out_wallets, ..] = fields_of(datum)
  expect out_recipient: VerificationKeyHash = out_recipient
  expect out_goal: Int = out_goal
  expect out_deadline: Int = out_deadline
  if and {
    out_recipient == recipient,
    out_goal == goal,
    out_deadline == deadline,
  } {
    Some(builtin.un_map_data(out_wallets))
  } else {
    None
  }
}

validator crowdfund {
  spend(
    datum: Option<Data>,
    redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(datum) = datum
    expect [recipient, goal, deadline, wallets, ..] = fields_of(datum)
    expect recipient: VerificationKeyHash = recipient
    expect goal: Int = goal
    expect deadline: Int = deadline
    let wallets = builtin.un_map_data(wallets)

    let Transaction { inputs, outputs, validity_range, extra_signatories, .. } = self

    expect Some(own_input) = transaction.find_input(inputs, own_ref)
    let contract_address = own_input.output.address

    let contract_amount = pairs.foldr(
      wallets,
      0,
      fn(_, v, acc) { builtin.un_i_data(v) + acc },
    )
    let contract_input_ada = list.foldl(
      inputs,
      0,
      fn(input, acc) {
        if input.output.address == contract_address {
          acc + assets.lovelace_of(input.output.value)
        } else {
          acc
        }
      },
    )
    let is_contract_output = fn(output: Output) {
      output.address == contract_address
    }

    let Pair(index, fields) = builtin.un_constr_data(redeemer)

    and {
      contract_amount == contract_input_ada,
      when index is {
        // Donate amount donor
        0 -> {
          expect [amount, donor, ..] = fields
          expect amount: Int = amount
          expect donor: VerificationKeyHash = donor
          let donor_key: Data = donor
          when list.filter(outputs, is_contract_output) is {
            [contract_output] -> and {
                starts_before(validity_range, deadline),
                list.has(extra_signatories, donor),
                assets.lovelace_of(contract_output.value) == contract_amount + amount,
                when
                  continuing_wallets(contract_output, recipient, goal, deadline)
                is {
                  Some(out_wallets) -> and {
                      pairs.delete_first(wallets, donor_key) == pairs.delete_first(
                        out_wallets,
                        donor_key,
                      ),
                      when pairs.get_first(out_wallets, donor_key) is {
                        Some(out_amount) -> {
                          let out_amount = builtin.un_i_data(out_amount)
                          when pairs.get_first(wallets, donor_key) is {
                            Some(previous) ->
                              out_amount == builtin.un_i_data(previous) + amount
                            None -> amount == out_amount
                          }
                        }
                        None -> False
                      },
                    }
                  None -> False
                },
              }
            _ -> False
          }
        }

        // Withdraw
        1 -> and {
            list.has(extra_signatories, recipient),
            !starts_before(validity_range, deadline),
            contract_amount >= goal,
          }

        // Reclaim
        2 -> {
          expect [current_signer, ..] = extra_signatories
          let signer_key: Data = current_signer
          when pairs.get_first(wallets, signer_key) is {
            Some(withdraw_amount) -> and {
                !starts_before(validity_range, deadline),
                when wallets is {
                  [_, _, ..] ->
                    when list.filter(outputs, is_contract_output) is {
                      [contract_output] -> and {
                          assets.lovelace_of(contract_output.value) == contract_input_ada - builtin.un_i_data(
                            withdraw_amount,
                          ),
                          when
                            continuing_wallets(
                              contract_output,
                              recipient,
                              goal,
                              deadline,
                            )
                          is {
                            Some(out_wallets) ->
                              out_wallets == pairs.delete_first(
                                wallets,
                                signer_key,
                              )
                            None -> False
                          },
                        }
                      _ -> False
                    }
                  _ -> !list.any(outputs, is_contract_output)
                },
              }
            None -> False
          }
        }

        _ -> fail
      },
    }
  }

  else(_) {
    fail
  }
}
