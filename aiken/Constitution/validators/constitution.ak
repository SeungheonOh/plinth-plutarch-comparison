use aiken/builtin
use aiken/collection/list
use cardano/governance.{
  ProposalProcedure, ProtocolParameters, TreasuryWithdrawal,
}
use cardano/transaction.{Transaction}
use types.{
  ConfigEntry, Fraction, IntPredicate, MaxValue, MinValue, NotEqual, ParamAny,
  ParamInteger, ParamList, ParamRational, ParamValue, RationalPredicate,
}

fn validate_int(predicates: List<IntPredicate>, actual: Int) -> Bool {
  list.all(
    predicates,
    fn(IntPredicate { key, expected }) {
      when key is {
        MinValue -> list.all(expected, fn(bound) { bound <= actual })
        MaxValue -> list.all(expected, fn(bound) { bound >= actual })
        NotEqual -> list.all(expected, fn(bound) { bound != actual })
      }
    },
  )
}

fn validate_rational(
  predicates: List<RationalPredicate>,
  numerator: Int,
  denominator: Int,
) -> Bool {
  list.all(
    predicates,
    fn(RationalPredicate { key, expected }) {
      when key is {
        MinValue ->
          list.all(
            expected,
            fn(Fraction { numerator: n, denominator: d }) {
              n * denominator <= numerator * d
            },
          )
        MaxValue ->
          list.all(
            expected,
            fn(Fraction { numerator: n, denominator: d }) {
              n * denominator >= numerator * d
            },
          )
        NotEqual ->
          list.all(
            expected,
            fn(Fraction { numerator: n, denominator: d }) {
              n * denominator != numerator * d
            },
          )
      }
    },
  )
}

fn validate_param(rule: ParamValue, actual: Data) -> Bool {
  when rule is {
    ParamInteger(predicates) -> {
      expect actual: Int = actual
      validate_int(predicates, actual)
    }
    ParamRational(predicates) -> {
      expect [numerator, denominator, ..]: List<Data> = actual
      expect numerator: Int = numerator
      expect denominator: Int = denominator
      validate_rational(predicates, numerator, denominator)
    }
    ParamList(rules) -> {
      expect actual: List<Data> = actual
      validate_params(rules, actual)
    }
    ParamAny -> True
  }
}

/// Element-wise validation; both lists must have the same length.
fn validate_params(rules: List<ParamValue>, actuals: List<Data>) -> Bool {
  when rules is {
    [] ->
      when actuals is {
        [] -> True
        _ -> False
      }
    [rule, ..rules] ->
      when actuals is {
        [] -> False
        [actual, ..actuals] ->
          validate_param(rule, actual) && validate_params(rules, actuals)
      }
  }
}

/// Merge-join of the (sorted) config against the (sorted) changed parameters:
/// every changed parameter must have a config entry, and satisfy it.
fn run_rules(config: List<ConfigEntry>, changed: Pairs<Data, Data>) -> Bool {
  when changed is {
    [] -> True
    [Pair(param_id, actual), ..changed] ->
      check_param(config, builtin.un_i_data(param_id), actual, changed)
  }
}

fn check_param(
  config: List<ConfigEntry>,
  param_id: Int,
  actual: Data,
  changed: Pairs<Data, Data>,
) -> Bool {
  when config is {
    [] -> False
    [ConfigEntry { param_id: expected_id, rule }, ..config] ->
      if param_id == expected_id {
        validate_param(rule, actual) && run_rules(config, changed)
      } else {
        param_id > expected_id && check_param(config, param_id, actual, changed)
      }
  }
}

validator constitution(config: List<ConfigEntry>) {
  propose(_redeemer: Data, proposal: ProposalProcedure, _self: Transaction) {
    when proposal.governance_action is {
      ProtocolParameters { new_parameters, .. } -> {
        let new_parameters: Data = new_parameters
        run_rules(config, builtin.un_map_data(new_parameters))
      }
      TreasuryWithdrawal { .. } -> True
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
