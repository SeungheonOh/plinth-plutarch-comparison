use aiken/builtin
use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Finite}
use cardano/address.{VerificationKey}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}

/// Amount vested at `timestamp` under a linear schedule.
fn linear_vesting(start: Int, duration: Int, total: Int, timestamp: Int) -> Int {
  if timestamp < start {
    0
  } else if timestamp > start + duration {
    total
  } else {
    total * ( timestamp - start ) / duration
  }
}

/// Adds the lovelace of `output` to `total` when it is locked by the
/// verification key `vkh`.
fn add_lovelace_paid_to(
  output: Output,
  vkh: VerificationKeyHash,
  total: Int,
) -> Int {
  when output.address.payment_credential is {
    VerificationKey(owner) ->
      if owner == vkh {
        total + assets.expect_lovelace_of(output.value)
      } else {
        total
      }
    _ -> total
  }
}

/// Fields of a single-constructor value encoded as `Constr _ fields`. As with
/// the `asData` encoding of the reference contract, the constructor index is
/// not inspected and trailing fields are ignored.
fn fields_of(data: Data) -> List<Data> {
  builtin.snd_pair(builtin.un_constr_data(data))
}

validator vesting {
  /// Datum: `VestingDatum beneficiary start duration amount`.
  /// Redeemer: `Release declared_amount`.
  spend(
    datum: Option<Data>,
    redeemer: Data,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(datum) = datum
    let datum_fields = fields_of(datum)
    expect [beneficiary, start_timestamp, duration, amount, ..] = datum_fields
    expect beneficiary: VerificationKeyHash = beneficiary
    expect start_timestamp: Int = start_timestamp
    expect duration: Int = duration
    expect amount: Int = amount
    expect [declared, ..] = fields_of(redeemer)
    expect declared: Int = declared
    let  
        Transaction {
          inputs,
          outputs,
          fee,
          validity_range,
          extra_signatories,
          ..
        }
      = self

    and {
      list.has(extra_signatories, beneficiary),
      {
        expect Some(Input { output: own_output, .. }) = transaction.find_input(
          inputs,
          own_ref,
        )
        let contract_amount = assets.expect_lovelace_of(own_output.value)
        let earliest = when validity_range.lower_bound.bound_type is {
          Finite(t) -> t
          _ -> 0
        }
        let released = amount - contract_amount
        let release_amount = linear_vesting(
          start_timestamp,
          duration,
          amount,
          earliest,
        ) - released
        and {
          declared == release_amount,
          list.foldl(
            outputs,
            0,
            fn(output, total) {
              add_lovelace_paid_to(output, beneficiary, total)
            },
          ) == declared + list.foldl(
            inputs,
            0,
            fn(input, total) {
              add_lovelace_paid_to(input.output, beneficiary, total)
            },
          ) - fee,
          or {
            declared == contract_amount,
            when
              list.filter(
                outputs,
                fn(output) { output.address == own_output.address },
              )
            is {
              [continuing] -> continuing.datum == InlineDatum(datum)
              _ -> False
            },
          },
        }
      },
    }
  }

  else(_) {
    fail
  }
}
