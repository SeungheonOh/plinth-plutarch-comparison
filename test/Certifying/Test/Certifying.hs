{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-name-shadowing #-}

module Certifying.Test.Certifying (
  mkCertifyingTests,
  mkCertifyingConformanceTests,
  certifyingBenchScenarios,
  certifyingUnitCases,
) where

import Data.Either (isRight)
import Plutarch.Evaluate (applyArguments, evalScript)
import Plutarch.Script (Script)
import PlutusLedgerApi.V1.Interval (interval)
import PlutusLedgerApi.V3
import PlutusTx qualified
import ProgrammableTokens.Test.ScriptContext.Builder (
  buildScriptContext,
  withCertifyingScript,
  withValidRange,
 )
import Test.QuickCheck qualified as QC
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase)
import Test.Tasty.QuickCheck (testProperty)

-- ============================================================================
-- Constants
-- ============================================================================

expiration :: Integer
expiration = 1_700_000_000_000

someCred :: Credential
someCred = ScriptCredential (ScriptHash "aabbccdd")

somePkh :: PubKeyHash
somePkh = PubKeyHash "11223344"

-- ============================================================================
-- Validity range helpers
-- ============================================================================

afterExpiration :: POSIXTimeRange
afterExpiration = interval (POSIXTime (expiration + 1)) (POSIXTime (expiration + 100_000))

beforeExpiration :: POSIXTimeRange
beforeExpiration = interval (POSIXTime (expiration - 100_000)) (POSIXTime (expiration - 1))

straddlesExpiration :: POSIXTimeRange
straddlesExpiration = interval (POSIXTime (expiration - 50_000)) (POSIXTime (expiration + 50_000))

-- ============================================================================
-- Context construction
-- ============================================================================

mkCertifyingContext :: TxCert -> POSIXTimeRange -> ScriptContext
mkCertifyingContext cert validRange =
  buildScriptContext
    ( withCertifyingScript (PlutusTx.toBuiltinData ()) cert
        <> withValidRange validRange
    )

-- ============================================================================
-- Positive test contexts
-- ============================================================================

posRegister :: ScriptContext
posRegister = mkCertifyingContext (TxCertRegStaking someCred (Just 2_000_000)) always

posUnregisterAfterExpiration :: ScriptContext
posUnregisterAfterExpiration =
  mkCertifyingContext (TxCertUnRegStaking someCred (Just 2_000_000)) afterExpiration

posDelegateAbstain :: ScriptContext
posDelegateAbstain =
  mkCertifyingContext (TxCertDelegStaking someCred (DelegVote DRepAlwaysAbstain)) always

posRegDelegAbstain :: ScriptContext
posRegDelegAbstain =
  mkCertifyingContext (TxCertRegDeleg someCred (DelegVote DRepAlwaysAbstain) 2_000_000) always

posRegisterNoDeposit :: ScriptContext
posRegisterNoDeposit =
  mkCertifyingContext (TxCertRegStaking someCred Nothing) always

-- ============================================================================
-- Negative test contexts
-- ============================================================================

negUnregisterBeforeExpiration :: ScriptContext
negUnregisterBeforeExpiration =
  mkCertifyingContext (TxCertUnRegStaking someCred (Just 2_000_000)) beforeExpiration

negUnregisterStraddlesExpiration :: ScriptContext
negUnregisterStraddlesExpiration =
  mkCertifyingContext (TxCertUnRegStaking someCred (Just 2_000_000)) straddlesExpiration

negDelegateNoConfidence :: ScriptContext
negDelegateNoConfidence =
  mkCertifyingContext (TxCertDelegStaking someCred (DelegVote DRepAlwaysNoConfidence)) always

negDelegateStake :: ScriptContext
negDelegateStake =
  mkCertifyingContext (TxCertDelegStaking someCred (DelegStake somePkh)) always

negDelegateSpecificDRep :: ScriptContext
negDelegateSpecificDRep =
  mkCertifyingContext
    (TxCertDelegStaking someCred (DelegVote (DRep (DRepCredential (PubKeyCredential somePkh)))))
    always

negRegDelegNoConfidence :: ScriptContext
negRegDelegNoConfidence =
  mkCertifyingContext (TxCertRegDeleg someCred (DelegVote DRepAlwaysNoConfidence) 2_000_000) always

negRegDelegStake :: ScriptContext
negRegDelegStake =
  mkCertifyingContext (TxCertRegDeleg someCred (DelegStake somePkh) 2_000_000) always

negPoolRegister :: ScriptContext
negPoolRegister =
  mkCertifyingContext (TxCertPoolRegister somePkh somePkh) always

negPoolRetire :: ScriptContext
negPoolRetire =
  mkCertifyingContext (TxCertPoolRetire somePkh 100) always

negAuthHotCommittee :: ScriptContext
negAuthHotCommittee =
  mkCertifyingContext
    (TxCertAuthHotCommittee (ColdCommitteeCredential someCred) (HotCommitteeCredential someCred))
    always

negDelegStakeVoteAbstain :: ScriptContext
negDelegStakeVoteAbstain =
  mkCertifyingContext (TxCertDelegStaking someCred (DelegStakeVote somePkh DRepAlwaysAbstain)) always

negRegDelegStakeVoteAbstain :: ScriptContext
negRegDelegStakeVoteAbstain =
  mkCertifyingContext
    (TxCertRegDeleg someCred (DelegStakeVote somePkh DRepAlwaysAbstain) 2_000_000)
    always

negUnregisterAlways :: ScriptContext
negUnregisterAlways =
  mkCertifyingContext (TxCertUnRegStaking someCred (Just 2_000_000)) always

-- ============================================================================
-- Test runner
-- ============================================================================

mkCertifyingTests :: String -> Script -> TestTree
mkCertifyingTests name script =
  let eval exp ctx =
        let (res, _budget, _logs) = evalScript (applyArguments script [PlutusTx.toData exp, PlutusTx.toData ctx])
         in isRight res
      assertSucceeds exp ctx =
        let (res, _budget, logs) = evalScript (applyArguments script [PlutusTx.toData exp, PlutusTx.toData ctx])
         in assertBool ("expected success, got: " ++ show res ++ " logs: " ++ show logs) (isRight res)
      assertFails exp ctx =
        assertBool "expected script failure" (not (eval exp ctx))
   in testGroup
        name
        [ testGroup
            groupName
            [ testCase caseName $ if shouldSucceed then assertSucceeds exp ctx else assertFails exp ctx
            | (caseName, shouldSucceed, exp, ctx) <- cases
            ]
        | (groupName, cases) <- certifyingUnitCases
        ]

{- | Named unit cases, grouped as in the test tree: (test name, expected to
succeed, expiration argument, script context).
-}
certifyingUnitCases :: [(String, [(String, Bool, Integer, ScriptContext)])]
certifyingUnitCases =
  [
    ( "Positive"
    ,
      [ ("register_credential", True, expiration, posRegister)
      , ("register_no_deposit", True, expiration, posRegisterNoDeposit)
      , ("unregister_after_expiration", True, expiration, posUnregisterAfterExpiration)
      , ("delegate_to_abstain", True, expiration, posDelegateAbstain)
      , ("register_and_delegate_to_abstain", True, expiration, posRegDelegAbstain)
      ]
    )
  ,
    ( "Negative"
    ,
      [ ("unregister_before_expiration", False, expiration, negUnregisterBeforeExpiration)
      , ("unregister_straddles_expiration", False, expiration, negUnregisterStraddlesExpiration)
      , ("unregister_always_range", False, expiration, negUnregisterAlways)
      , ("delegate_no_confidence", False, expiration, negDelegateNoConfidence)
      , ("delegate_to_stake_pool", False, expiration, negDelegateStake)
      , ("delegate_specific_drep", False, expiration, negDelegateSpecificDRep)
      , ("delegate_stake_vote_abstain", False, expiration, negDelegStakeVoteAbstain)
      , ("register_delegate_no_confidence", False, expiration, negRegDelegNoConfidence)
      , ("register_delegate_stake_pool", False, expiration, negRegDelegStake)
      , ("register_delegate_stake_vote_abstain", False, expiration, negRegDelegStakeVoteAbstain)
      , ("pool_register", False, expiration, negPoolRegister)
      , ("pool_retire", False, expiration, negPoolRetire)
      , ("auth_hot_committee", False, expiration, negAuthHotCommittee)
      ]
    )
  ]

-- ============================================================================
-- Benchmark scenarios
-- ============================================================================

certifyingBenchScenarios :: [(String, Integer, ScriptContext)]
certifyingBenchScenarios =
  [ ("register credential", expiration, posRegister)
  , ("unregister after expiration", expiration, posUnregisterAfterExpiration)
  , ("delegate to abstain", expiration, posDelegateAbstain)
  , ("register+delegate to abstain", expiration, posRegDelegAbstain)
  , ("unregister before expiration (reject)", expiration, negUnregisterBeforeExpiration)
  , ("delegate no confidence (reject)", expiration, negDelegateNoConfidence)
  , ("delegate stake pool (reject)", expiration, negDelegateStake)
  , ("pool register (reject)", expiration, negPoolRegister)
  ]

-- ============================================================================
-- Conformance property test
-- ============================================================================

evalScript' :: Script -> Integer -> ScriptContext -> Bool
evalScript' script exp ctx =
  let (res, _, _) = evalScript (applyArguments script [PlutusTx.toData exp, PlutusTx.toData ctx])
   in isRight res

genDelegatee :: QC.Gen Delegatee
genDelegatee =
  QC.oneof
    [ pure (DelegStake somePkh)
    , DelegVote <$> genDRep
    , DelegStakeVote somePkh <$> genDRep
    ]

genDRep :: QC.Gen DRep
genDRep =
  QC.oneof
    [ pure DRepAlwaysAbstain
    , pure DRepAlwaysNoConfidence
    , pure (DRep (DRepCredential (PubKeyCredential somePkh)))
    ]

genTxCert :: QC.Gen TxCert
genTxCert =
  QC.oneof
    [ TxCertRegStaking someCred
        <$> QC.oneof [pure Nothing, Just . Lovelace <$> QC.chooseInteger (0, 5_000_000)]
    , TxCertUnRegStaking someCred
        <$> QC.oneof [pure Nothing, Just . Lovelace <$> QC.chooseInteger (0, 5_000_000)]
    , TxCertDelegStaking someCred <$> genDelegatee
    , TxCertRegDeleg someCred <$> genDelegatee <*> (Lovelace <$> QC.chooseInteger (0, 5_000_000))
    , pure (TxCertPoolRegister somePkh somePkh)
    , TxCertPoolRetire somePkh <$> QC.chooseInteger (0, 100)
    , pure (TxCertAuthHotCommittee (ColdCommitteeCredential someCred) (HotCommitteeCredential someCred))
    , pure (TxCertResignColdCommittee (ColdCommitteeCredential someCred))
    ]

genValidityRange :: Integer -> QC.Gen POSIXTimeRange
genValidityRange exp = do
  lo <- QC.chooseInteger (exp - 200_000, exp + 200_000)
  hi <- QC.chooseInteger (lo, lo + 200_000)
  pure $ interval (POSIXTime lo) (POSIXTime hi)

mkCertifyingConformanceTests :: Script -> Script -> TestTree
mkCertifyingConformanceTests plutarchScript plinthScript =
  testGroup
    "Plutarch-Plinth Conformance"
    [ testProperty "prop_both_scripts_agree" $
        QC.forAll (QC.chooseInteger (1_000_000_000_000, 2_000_000_000_000)) $ \exp ->
          QC.forAll genTxCert $ \cert ->
            QC.forAll (genValidityRange exp) $ \validRange ->
              let ctx = mkCertifyingContext cert validRange
                  plutarchResult = evalScript' plutarchScript exp ctx
                  plinthResult = evalScript' plinthScript exp ctx
               in plutarchResult QC.=== plinthResult
    ]
