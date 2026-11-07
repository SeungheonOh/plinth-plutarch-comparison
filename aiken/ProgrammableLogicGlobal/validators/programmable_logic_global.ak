use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId}
use cardano/script_context.{ScriptContext}
use cardano/transaction.{
  InlineDatum, Input, Output, Redeemer, ScriptPurpose, Spend, Transaction,
}
use programmable/value.{Bundle, TokenList}

// User-supplied data is read field by field, the way the specification reads
// its data-encoded types: single-constructor records are not tag-checked,
// trailing fields are ignored, and credentials are kept (and compared) as raw
// `Data`.
//
//   redeemer   TransferAct { transfer_proofs: [Int], mint_proofs: [Int] }   (tag 0)
//              SeizeAct { directory_node_idx: Int, input_idxs: [Int],
//                         outputs_start_idx: Int, length_input_idxs: Int } (tag 1)
//   params     { directory_node_cs: PolicyId, prog_logic_cred: Credential }
//   node       { key: PolicyId, next: PolicyId, transfer_logic_script: Credential,
//                issuer_logic_script: Credential, global_state_cs: PolicyId }

validator programmable_logic_global(protocol_params_cs: PolicyId) {
  withdraw(redeemer: Data, _account: Credential, self: Transaction) {
    let (directory_node_cs, prog_logic_cred) = protocol_params(
      protocol_params_cs,
      self.reference_inputs,
    )
    let action = builtin.un_constr_data(redeemer)
    let fields = action.2nd
    when action.1st is {
      0 -> {
        expect [transfer_proofs, ..later_fields] = fields
        transfer(
          directory_node_cs,
          prog_logic_cred,
          self,
          builtin.un_list_data(transfer_proofs),
          later_fields,
        )
      }
      1 -> seize(directory_node_cs, prog_logic_cred, self, fields)
      _ -> fail
    }
  }

  // Seizures do not depend on the purpose the script runs under; transfers
  // are only valid as a withdrawal.
  else(ctx: ScriptContext) {
    let self = ctx.transaction
    let (directory_node_cs, prog_logic_cred) = protocol_params(
      protocol_params_cs,
      self.reference_inputs,
    )
    let action = builtin.un_constr_data(ctx.redeemer)
    expect action.1st == 1
    seize(directory_node_cs, prog_logic_cred, self, action.2nd)
  }
}

// ----------------------------------------------------------------------------
// Reference data
// ----------------------------------------------------------------------------

/// Fields of the inline datum of an output, whatever its constructor tag.
fn datum_fields(output: Output) -> List<Data> {
  expect InlineDatum(datum) = output.datum
  builtin.un_constr_data(datum).2nd
}

/// The directory node policy and the programmable-logic credential.
fn protocol_params(
  protocol_params_cs: PolicyId,
  reference_inputs: List<Input>,
) -> (PolicyId, Data) {
  expect Some(Input { output, .. }) = list.find(
    reference_inputs,
    fn(input) {
      value.has_policy_first_non_ada(input.output.value, protocol_params_cs)
    },
  )
  expect [directory_node_cs, prog_logic_cred, ..] = datum_fields(output)
  (builtin.un_b_data(directory_node_cs), prog_logic_cred)
}

/// The reference input output at `index`, holding a directory node.
fn directory_node_output(reference_inputs: List<Input>, index: Int) -> Output {
  expect Some(Input { output, .. }) = list.at(reference_inputs, index)
  output
}

fn is_invoked(credential: Data, withdrawals: Pairs<Credential, Int>) -> Bool {
  when withdrawals is {
    [] -> False
    [Pair(withdrawal, _), ..rest] -> {
      let withdrawal: Data = withdrawal
      withdrawal == credential || is_invoked(credential, rest)
    }
  }
}

// ----------------------------------------------------------------------------
// Transfer
// ----------------------------------------------------------------------------

fn transfer(
  directory_node_cs: PolicyId,
  prog_logic_cred: Data,
  self: Transaction,
  transfer_proofs: List<Data>,
  later_fields: List<Data>,
) -> Bool {
  let  
      Transaction {
        inputs,
        reference_inputs,
        outputs,
        mint,
        withdrawals,
        extra_signatories,
        ..
      }
    = self
  expect [Pair(first_withdrawal, _), ..] = withdrawals
  let programmable_value = programmable_transfer_value(
    directory_node_cs,
    reference_inputs,
    withdrawals,
    transfer_proofs,
    value_from_cred(prog_logic_cred, extra_signatories, withdrawals, inputs),
    first_withdrawal,
  )
  let expected = if assets.is_zero(mint) {
    programmable_value
  } else {
    // The mint proofs are only read when something is minted.
    expect [mint_proofs, ..] = later_fields
    value.union(
      programmable_value,
      programmable_mint_value(
        directory_node_cs,
        reference_inputs,
        withdrawals,
        builtin.un_list_data(mint_proofs),
        assets.to_pairs(mint),
      ),
    )
  }
  outputs_contain_expected_value(prog_logic_cred, outputs, expected)
}

fn is_at(output: Output, cred: Data) -> Bool {
  let payment_credential: Data = output.address.payment_credential
  payment_credential == cred
}

/// Non-Ada value of all inputs held at the programmable-logic credential;
/// every such input must be authorised by its stake credential.
fn value_from_cred(
  cred: Data,
  signatories: List<VerificationKeyHash>,
  withdrawals: Pairs<Credential, Int>,
  inputs: List<Input>,
) -> Bundle {
  list.foldl(
    inputs,
    [],
    fn(input, acc) {
      let output = input.output
      if is_at(output, cred) {
        expect Some(Inline(owner)) = output.address.stake_credential
        let authorised = when owner is {
          VerificationKey(pkh) -> list.has(signatories, pkh)
          Script(_) -> is_invoked(owner, withdrawals)
        }
        if authorised {
          value.union(acc, value.strip_ada(output.value))
        } else {
          fail
        }
      } else {
        acc
      }
    },
  )
}

/// Walk the policies of `total` alongside their directory proofs and keep the
/// programmable ones, checking that their transfer logic was invoked.
fn programmable_transfer_value(
  directory_node_cs: PolicyId,
  reference_inputs: List<Input>,
  withdrawals: Pairs<Credential, Int>,
  proofs: List<Data>,
  total: Bundle,
  cached_transfer_script: Data,
) -> Bundle {
  when total is {
    [] -> []
    [Pair(policy, _) as entry, ..rest] -> {
      expect [proof, ..proofs_rest] = proofs
      let node_output = directory_node_output(
        reference_inputs,
        builtin.un_i_data(proof),
      )
      expect [key,
            next,
            transfer_logic_script,
            _, global_state_cs, ..] = datum_fields(node_output)
      let key = builtin.un_b_data(key)
      expect _ = builtin.un_b_data(next)
      let next = builtin.un_b_data(next)
      expect _ = builtin.un_b_data(global_state_cs)
      let valid_node = value.has_policy_first_non_ada(
        node_output.value,
        directory_node_cs,
      )
      if builtin.less_than_bytearray(key, policy) {
        // Not programmable: the node proves the policy is absent.
        if builtin.less_than_bytearray(policy, next) && valid_node {
          programmable_transfer_value(
            directory_node_cs,
            reference_inputs,
            withdrawals,
            proofs_rest,
            rest,
            cached_transfer_script,
          )
        } else {
          fail
        }
      } else if and {
        or {
          transfer_logic_script == cached_transfer_script,
          is_invoked(transfer_logic_script, withdrawals),
        },
        key == policy,
        valid_node,
      } {
        [
          entry,
          ..programmable_transfer_value(
            directory_node_cs,
            reference_inputs,
            withdrawals,
            proofs_rest,
            rest,
            transfer_logic_script,
          )
        ]
      } else {
        fail
      }
    }
  }
}

/// Walk the minted policies alongside their directory proofs (exactly one
/// proof per policy) and keep the programmable ones.
fn programmable_mint_value(
  directory_node_cs: PolicyId,
  reference_inputs: List<Input>,
  withdrawals: Pairs<Credential, Int>,
  proofs: List<Data>,
  minted: Bundle,
) -> Bundle {
  when minted is {
    [] ->
      if proofs == [] {
        []
      } else {
        fail
      }
    [Pair(policy, _) as entry, ..rest] -> {
      expect [proof, ..proofs_rest] = proofs
      let node_output = directory_node_output(
        reference_inputs,
        builtin.un_i_data(proof),
      )
      expect [key,
            next,
            transfer_logic_script,
            _, global_state_cs, ..] = datum_fields(node_output)
      let key = builtin.un_b_data(key)
      expect _ = builtin.un_b_data(next)
      let next = builtin.un_b_data(next)
      expect _ = builtin.un_b_data(global_state_cs)
      let valid_node = value.has_policy_first_non_ada(
        node_output.value,
        directory_node_cs,
      )
      if key == policy {
        if is_invoked(transfer_logic_script, withdrawals) && valid_node {
          [
            entry,
            ..programmable_mint_value(
              directory_node_cs,
              reference_inputs,
              withdrawals,
              proofs_rest,
              rest,
            )
          ]
        } else {
          fail
        }
      } else if and {
        builtin.less_than_bytearray(key, policy),
        builtin.less_than_bytearray(policy, next),
        valid_node,
      } {
        programmable_mint_value(
          directory_node_cs,
          reference_inputs,
          withdrawals,
          proofs_rest,
          rest,
        )
      } else {
        fail
      }
    }
  }
}

fn outputs_contain_expected_value(
  cred: Data,
  outputs: List<Output>,
  expected: Bundle,
) -> Bool {
  when expected is {
    [] -> True
    [Pair(policy, tokens)] ->
      when dict.to_pairs(tokens) is {
        [] -> True
        [Pair(name, required)] ->
          has_at_least_at_cred(cred, outputs, policy, name, required, 0)
        _ -> multi_asset_check(cred, outputs, expected)
      }
    _ -> multi_asset_check(cred, outputs, expected)
  }
}

fn has_at_least_at_cred(
  cred: Data,
  outputs: List<Output>,
  policy: PolicyId,
  name: AssetName,
  required: Int,
  current: Int,
) -> Bool {
  if current >= required {
    True
  } else {
    when outputs is {
      [] -> False
      [output, ..rest] ->
        if is_at(output, cred) {
          has_at_least_at_cred(
            cred,
            rest,
            policy,
            name,
            required,
            current + assets.quantity_of(output.value, policy, name),
          )
        } else {
          has_at_least_at_cred(cred, rest, policy, name, required, current)
        }
    }
  }
}

fn multi_asset_check(
  cred: Data,
  outputs: List<Output>,
  expected: Bundle,
) -> Bool {
  let actual = list.foldl(
    outputs,
    [],
    fn(output, acc) {
      if is_at(output, cred) {
        value.union(acc, value.strip_ada(output.value))
      } else {
        acc
      }
    },
  )
  list.all(
    expected,
    fn(Pair(policy, tokens)) {
      list.all(
        dict.to_pairs(tokens),
        fn(Pair(name, required)) {
          value.bundle_quantity_of(actual, policy, name) >= required
        },
      )
    },
  )
}

// ----------------------------------------------------------------------------
// Seize
// ----------------------------------------------------------------------------

fn seize(
  directory_node_cs: PolicyId,
  prog_logic_cred: Data,
  self: Transaction,
  fields: List<Data>,
) -> Bool {
  expect  
      [directory_node_idx, input_idxs, outputs_start_idx, length_input_idxs, ..]
    = fields
  let directory_node_idx = builtin.un_i_data(directory_node_idx)
  let input_idxs = builtin.un_list_data(input_idxs)
  let outputs_start_idx = builtin.un_i_data(outputs_start_idx)
  let length_input_idxs = builtin.un_i_data(length_input_idxs)
  let  
      Transaction {
        inputs,
        reference_inputs,
        outputs,
        mint,
        withdrawals,
        redeemers,
        ..
      }
    = self
  let node_output = directory_node_output(reference_inputs, directory_node_idx)
  expect [key,
        next,
        _, issuer_logic_script, global_state_cs, ..] = datum_fields(node_output)
  let programmable_cs = builtin.un_b_data(key)
  expect _ = builtin.un_b_data(next)
  expect _ = builtin.un_b_data(global_state_cs)
  and {
    third_party_transfer(
      programmable_cs,
      prog_logic_cred,
      input_idxs,
      inputs,
      list.drop(outputs, outputs_start_idx),
      [],
      dict.to_pairs(assets.tokens(mint, programmable_cs)),
    ),
    is_invoked(issuer_logic_script, withdrawals),
    value.has_policy_first_non_ada(node_output.value, directory_node_cs),
    enforce_n_spend_redeemers(length_input_idxs, redeemers),
    list.length(input_idxs) == length_input_idxs,
  }
}

/// Pair every selected programmable input with the next programmable output,
/// accumulating the change in programmable tokens; the remaining programmable
/// outputs must then hold that change plus whatever was minted.
fn third_party_transfer(
  programmable_cs: PolicyId,
  prog_logic_cred: Data,
  idxs: List<Data>,
  inputs: List<Input>,
  programmable_outputs: List<Output>,
  delta: TokenList,
  minted: TokenList,
) -> Bool {
  when idxs is {
    [] ->
      value.tokens_contain(
        programmable_output_tokens(
          programmable_cs,
          prog_logic_cred,
          programmable_outputs,
        ),
        value.tokens_union(delta, minted),
      )
    [relative_idx, ..rest_idxs] -> {
      expect [input, ..after_input] = list.drop(
        inputs,
        builtin.un_i_data(relative_idx),
      )
      let input_output = input.output
      if is_at(input_output, prog_logic_cred) {
        expect [output, ..outputs_rest] = programmable_outputs
        if and {
          output.address == input_output.address,
          output.datum == input_output.datum,
          output.reference_script == input_output.reference_script,
        } {
          third_party_transfer(
            programmable_cs,
            prog_logic_cred,
            rest_idxs,
            after_input,
            outputs_rest,
            value.tokens_union(
              programmable_delta(
                programmable_cs,
                input_output.value,
                output.value,
              ),
              delta,
            ),
            minted,
          )
        } else {
          fail
        }
      } else {
        expect Script(_) = input_output.address.payment_credential
        third_party_transfer(
          programmable_cs,
          prog_logic_cred,
          rest_idxs,
          after_input,
          programmable_outputs,
          delta,
          minted,
        )
      }
    }
  }
}

/// Change in `programmable_cs` tokens between a seized input value and its
/// corresponding output value; every other policy must be left untouched.
fn programmable_delta(
  programmable_cs: PolicyId,
  input_value: assets.Assets,
  output_value: assets.Assets,
) -> TokenList {
  do_programmable_delta(
    programmable_cs,
    assets.to_pairs(input_value),
    assets.to_pairs(output_value),
  )
}

fn do_programmable_delta(
  programmable_cs: PolicyId,
  ins: Bundle,
  outs: Bundle,
) -> TokenList {
  when ins is {
    [] -> []
    [Pair(in_cs, in_tokens), ..ins_rest] ->
      when outs is {
        [] -> []
        [Pair(out_cs, out_tokens), ..outs_rest] ->
          if in_cs == out_cs {
            if in_cs == programmable_cs {
              if ins_rest == outs_rest {
                value.tokens_subtract(
                  dict.to_pairs(in_tokens),
                  dict.to_pairs(out_tokens),
                )
              } else {
                fail
              }
            } else if in_tokens == out_tokens {
              do_programmable_delta(programmable_cs, ins_rest, outs_rest)
            } else {
              fail
            }
          } else if in_tokens == out_tokens {
            []
          } else {
            fail
          }
      }
  }
}

fn programmable_output_tokens(
  programmable_cs: PolicyId,
  prog_logic_cred: Data,
  outputs: List<Output>,
) -> TokenList {
  list.foldr(
    outputs,
    [],
    fn(output, acc) {
      if is_at(output, prog_logic_cred) {
        value.tokens_union(
          dict.to_pairs(assets.tokens(output.value, programmable_cs)),
          acc,
        )
      } else {
        acc
      }
    },
  )
}

fn is_spend(purpose: ScriptPurpose) -> Bool {
  when purpose is {
    Spend(_) -> True
    _ -> False
  }
}

/// The `n`-th redeemer is the last spending one.
fn enforce_n_spend_redeemers(
  n: Int,
  redeemers: Pairs<ScriptPurpose, Redeemer>,
) -> Bool {
  when list.drop(redeemers, n - 1) is {
    [] -> False
    [Pair(purpose, _), ..rest] ->
      is_spend(purpose) && when rest is {
        [] -> True
        [Pair(next, _), ..] -> !is_spend(next)
      }
  }
}
