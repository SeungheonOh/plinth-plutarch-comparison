use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use aiken/interval.{Finite, Interval}
use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, Input, OutputReference, Transaction}

// Datum: SettingsDatum with 12 fields (Constr _ [...]):
//   0 settings_admin   1 metadata_admin      2 treasury_admin
//   3 treasury_address 4 treasury_allowance  5 authorized_scoopers
//   6 authorized_staking_keys                7 base_fee
//   8 simple_fee       9 strategy_fee       10 pool_creation_fee
//  11 extensions
// Redeemer: SettingsAdminUpdate | TreasuryAdminUpdate (Constr 0 / Constr 1)
//
// Both are read straight from `Data`, the way the reference contract's
// `asData` accessors do: the datum's constructor index is not inspected,
// trailing fields are ignored, fields are compared as raw `Data`, and the
// admin multisig script is decoded node by node as it is evaluated.

/// Fields of a value encoded as `Constr _ fields`, ignoring the index.
fn fields_of(data: Data) -> List<Data> {
  builtin.snd_pair(builtin.un_constr_data(data))
}

/// Evaluates a multisig script encoded as
///   Signature key_hash        (0)    Before time      (4)
///   AllOf scripts             (1)    After time       (5)
///   AnyOf scripts             (2)    ScriptWit hash   (6)
///   AtLeast required scripts  (3)
fn satisfied(
  script: Data,
  signatories: List<VerificationKeyHash>,
  validity_range: Interval,
  withdrawals: Pairs<Credential, Int>,
) -> Bool {
  let Pair(index, fields) = builtin.un_constr_data(script)
  let satisfied_by = fn(s) {
    satisfied(s, signatories, validity_range, withdrawals)
  }
  when index is {
    0 -> {
      expect [key_hash, ..] = fields
      expect key_hash: VerificationKeyHash = key_hash
      list.has(signatories, key_hash)
    }
    1 -> {
      expect [scripts, ..] = fields
      list.all(builtin.un_list_data(scripts), satisfied_by)
    }
    2 -> {
      expect [scripts, ..] = fields
      list.any(builtin.un_list_data(scripts), satisfied_by)
    }
    3 -> {
      expect [required, scripts, ..] = fields
      expect required: Int = required
      required <= list.count(builtin.un_list_data(scripts), satisfied_by)
    }
    4 ->
      when validity_range.upper_bound.bound_type is {
        Finite(hi) -> {
          expect [time, ..] = fields
          expect time: Int = time
          if validity_range.upper_bound.is_inclusive {
            hi <= time
          } else {
            hi < time
          }
        }
        _ -> False
      }
    5 ->
      when validity_range.lower_bound.bound_type is {
        Finite(lo) -> {
          expect [time, ..] = fields
          expect time: Int = time
          if validity_range.lower_bound.is_inclusive {
            time <= lo
          } else {
            time < lo
          }
        }
        _ -> False
      }
    6 ->
      when withdrawals is {
        [] -> False
        _ -> {
          expect [script_hash, ..] = fields
          // The hash must be a bytestring, even though it is only ever
          // compared as part of a credential.
          if script_hash is hash: ScriptHash {
            pairs.has_key(withdrawals, Script(hash))
          } else {
            fail
          }
        }
      }
    _ -> fail
  }
}

/// Whether a settings datum carries at least its 12 fields. The reference
/// contract unpacks every field of both datums, even in branches that only
/// compare a few of them.
fn has_all_settings_fields(fields: List<Data>) -> Bool {
  list.drop(fields, 11) != []
}

fn mints_exactly_one_settings_token(
  mint: assets.Assets,
  policy_id: PolicyId,
) -> Bool {
  when assets.to_pairs(mint) is {
    [Pair(cs, tokens)] ->
      cs == policy_id && when dict.to_pairs(tokens) is {
        [Pair(token_name, quantity)] ->
          token_name == "settings" && quantity == 1
        _ -> False
      }
    _ -> False
  }
}

validator settings(boot_utxo: Data) {
  spend(
    datum: Option<Data>,
    redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(input_datum) = datum
    let  
        Transaction {
          inputs,
          outputs,
          mint,
          extra_signatories,
          validity_range,
          withdrawals,
          ..
        }
      = self

    expect Some(Input { output: own_input, .. }) = transaction.find_input(
      inputs,
      own_ref,
    )
    expect [own_output, ..] = outputs
    expect InlineDatum(output_datum) = own_output.datum
    let input_fields = fields_of(input_datum)
    let output_fields = fields_of(output_datum)

    and {
      own_output.address == own_input.address,
      assets.without_lovelace(own_output.value) == assets.without_lovelace(
        own_input.value,
      ),
      assets.is_zero(mint),
      when builtin.fst_pair(builtin.un_constr_data(redeemer)) is {
        // SettingsAdminUpdate
        0 -> {
          expect  
              [
                settings_admin, _, _, treasury_address, treasury_allowance, _,
                staking_keys,
                ..
              ]
            = input_fields
          expect  
              [
                _, _, _, out_treasury_address, out_treasury_allowance, _,
                out_staking_keys,
                ..
              ]
            = output_fields
          and {
            has_all_settings_fields(input_fields),
            has_all_settings_fields(output_fields),
            satisfied(
              settings_admin,
              extra_signatories,
              validity_range,
              withdrawals,
            ),
            staking_keys == out_staking_keys,
            treasury_address == out_treasury_address,
            treasury_allowance == out_treasury_allowance,
          }
        }
        // TreasuryAdminUpdate
        1 -> {
          expect  
              [
                settings_admin, metadata_admin, treasury_admin, _, _, scoopers,
                _, base_fee, simple_fee, strategy_fee, pool_creation_fee,
                extensions,
                ..
              ]
            = input_fields
          expect  
              [
                out_settings_admin, out_metadata_admin, out_treasury_admin, _, _,
                out_scoopers, _, out_base_fee, out_simple_fee, out_strategy_fee,
                out_pool_creation_fee, out_extensions,
                ..
              ]
            = output_fields
          and {
            satisfied(
              treasury_admin,
              extra_signatories,
              validity_range,
              withdrawals,
            ),
            settings_admin == out_settings_admin,
            metadata_admin == out_metadata_admin,
            treasury_admin == out_treasury_admin,
            scoopers == out_scoopers,
            base_fee == out_base_fee,
            simple_fee == out_simple_fee,
            strategy_fee == out_strategy_fee,
            pool_creation_fee == out_pool_creation_fee,
            extensions == out_extensions,
          }
        }
        _ -> fail
      },
    }
  }

  mint(_redeemer: Data, policy_id: PolicyId, self: Transaction) {
    and {
      mints_exactly_one_settings_token(self.mint, policy_id),
      list.any(
        self.inputs,
        fn(input) {
          let output_reference: Data = input.output_reference
          output_reference == boot_utxo
        },
      ),
      list.any(
        self.outputs,
        fn(output) {
          when output.address.payment_credential is {
            Script(script_hash) ->
              script_hash == policy_id && when output.datum is {
                InlineDatum(_) -> True
                _ -> False
              }
            _ -> False
          }
        },
      ),
    }
  }

  else(_) {
    fail
  }
}
