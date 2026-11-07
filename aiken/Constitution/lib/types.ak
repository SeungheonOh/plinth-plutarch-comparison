/// Comparison applied between each expected bound and the proposed value.
/// Encoded as `Constr 0 []`, `Constr 1 []`, `Constr 2 []`.
pub type PredKey {
  MinValue
  MaxValue
  NotEqual
}

/// `(PredKey, [Integer])`, i.e. `Constr 0 [key, [I ..]]`.
pub type IntPredicate {
  key: PredKey,
  expected: List<Int>,
}

/// `(Integer, Integer)`, i.e. `Constr 0 [I numerator, I denominator]`.
pub type Fraction {
  numerator: Int,
  denominator: Int,
}

/// `(PredKey, [(Integer, Integer)])`, i.e. `Constr 0 [key, [fraction ..]]`.
pub type RationalPredicate {
  key: PredKey,
  expected: List<Fraction>,
}

/// Guardrail for one protocol parameter.
pub type ParamValue {
  ParamInteger(List<IntPredicate>)
  ParamRational(List<RationalPredicate>)
  ParamList(List<ParamValue>)
  ParamAny
}

/// `(Integer, ParamValue)`, i.e. `Constr 0 [I param_id, rule]`.
pub type ConfigEntry {
  param_id: Int,
  rule: ParamValue,
}
