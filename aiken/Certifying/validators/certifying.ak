use aiken/interval
use cardano/certificate.{
  AlwaysAbstain, Certificate, DelegateCredential, DelegateVote,
  RegisterAndDelegateCredential, RegisterCredential, UnregisterCredential,
}
use cardano/transaction.{Transaction}

/// Stake-credential policy:
/// - registration is always allowed;
/// - deregistration only once the validity range lies entirely after `expiration`;
/// - delegation (alone or with registration) only to the always-abstain DRep.
validator certifying(expiration: Int) {
  publish(_redeemer: Data, certificate: Certificate, self: Transaction) {
    when certificate is {
      RegisterCredential { .. } -> True
      UnregisterCredential { .. } ->
        interval.is_entirely_after(self.validity_range, expiration)
      DelegateCredential { delegate, .. } -> delegate == DelegateVote(AlwaysAbstain)
      RegisterAndDelegateCredential { delegate, .. } ->
        delegate == DelegateVote(AlwaysAbstain)
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
