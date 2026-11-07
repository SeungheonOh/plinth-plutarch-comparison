{-# LANGUAGE PatternSynonyms #-}

{- | The validators of the cross-language benchmark, their Plinth and Plutarch
scripts, and the cases they are measured on.

Bench cases are the repo's cost-table scenarios (the same lists and argument
order 'BenchScripts' uses); test cases are the named accept/reject unit cases
of the conformance test suite, with the expectation taken from the test.
-}
module CrossBench.Cases (
  CaseKind (..),
  caseKindName,
  CaseSpec (..),
  ValidatorSpec (..),
  validatorSpecs,
) where

import Certifying.Contracts.Certifying (mkCertifyingValidator)
import Certifying.Contracts.CertifyingPlinth (plinthCertifyingScript)
import Certifying.Test.Certifying qualified as Certifying
import Constitution.Contracts.ConstitutionSorted (mkConstitutionValidator)
import Constitution.Contracts.ConstitutionSortedPlinth (plinthConstitutionScript)
import Constitution.Test.ConstitutionSorted qualified as ConstitutionSorted
import CrossBench.Eval (Program, programFromCompiledCode, programFromScript)
import Crowdfund.Contracts.Crowdfund (mkCrowdfundValidator)
import Crowdfund.Contracts.CrowdfundPlinth (plinthCrowdfundScript)
import Crowdfund.Test.Crowdfund qualified as Crowdfund
import Hydra.Contracts.Head (mkHeadValidator)
import Hydra.Contracts.HeadPlinth (plinthHeadScript)
import Hydra.Test.Head qualified as HydraHead
import Plutarch.Internal.Term (Config (NoTracing), Term, compile)
import Plutarch.Script (Script)
import PlutusCore.Data (Data)
import PlutusTx qualified
import ProgrammableTokens.Test.ProgrammableLogicGlobal qualified as ProgrammableLogicGlobal
import Sample.Sample qualified as SamplePlutarch
import Sample.SamplePlinth (Withdraw, pattern Amount, pattern Deduct, pattern Joint)
import Sample.SamplePlinth qualified as SamplePlinth
import Settings.Contracts.Settings (mkSettingsValidator)
import Settings.Contracts.SettingsPlinth (plinthSettingsScript)
import Settings.Test.Settings qualified as Settings
import SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)
import SmartTokens.Contracts.ProgrammableLogicBasePlinth (plinthProgrammableLogicGlobalScript)
import Vesting.Contracts.Vesting (mkVestingValidator)
import Vesting.Contracts.VestingPlinth (plinthVestingScript)
import Vesting.Test.Vesting qualified as Vesting
import Voting.Contracts.Voting (mkVotingValidator)
import Voting.Contracts.VotingPlinth (plinthVotingScript)
import Voting.Test.Voting qualified as Voting

data CaseKind = BenchCase | TestCase
  deriving stock (Eq, Ord, Show)

caseKindName :: CaseKind -> String
caseKindName BenchCase = "bench"
caseKindName TestCase = "test"

data CaseSpec = CaseSpec
  { csName :: String
  , csKind :: CaseKind
  , csExpectSuccess :: Maybe Bool
  -- ^ The test's assertion for test cases; 'Nothing' for bench cases, whose
  -- expectation is the Plinth result.
  , csArgs :: [Data]
  -- ^ The arguments applied to the script, in order.
  , csReference :: Maybe Integer
  -- ^ For integer-returning scripts, the value computed by the Haskell
  -- definition of the Plinth source, used as a cross-check.
  }

data ValidatorSpec = ValidatorSpec
  { vsName :: String
  , vsPlinth :: Program
  , vsPlutarch :: Program
  , vsReturnsInteger :: Bool
  -- ^ The script returns an Integer (Sample) instead of accepting/rejecting.
  , vsCases :: [CaseSpec]
  }

compileNoTracing :: (forall s. Term s a) -> Script
compileNoTracing term =
  either (error . ("compile failed: " <>) . show) id (compile NoTracing term)

bench :: String -> [Data] -> CaseSpec
bench name args = CaseSpec name BenchCase Nothing args Nothing

test :: String -> Bool -> [Data] -> CaseSpec
test name ok args = CaseSpec name TestCase (Just ok) args Nothing

validatorSpecs :: [ValidatorSpec]
validatorSpecs =
  [ ValidatorSpec
      { vsName = "Voting"
      , vsPlinth = programFromScript plinthVotingScript
      , vsPlutarch = programFromScript (compileNoTracing mkVotingValidator)
      , vsReturnsInteger = False
      , vsCases =
          [ bench name [PlutusTx.toData cs, PlutusTx.toData tn, PlutusTx.toData ctx]
          | (name, cs, tn, ctx) <- Voting.votingBenchScenarios
          ]
            ++ [ test (g ++ "/" ++ name) ok [PlutusTx.toData cs, PlutusTx.toData tn, PlutusTx.toData ctx]
               | (g, cases) <- Voting.votingUnitCases
               , (name, ok, cs, tn, ctx) <- cases
               ]
      }
  , ValidatorSpec
      { vsName = "Certifying"
      , vsPlinth = programFromScript plinthCertifyingScript
      , vsPlutarch = programFromScript (compileNoTracing mkCertifyingValidator)
      , vsReturnsInteger = False
      , vsCases =
          [ bench name [PlutusTx.toData expiration, PlutusTx.toData ctx]
          | (name, expiration, ctx) <- Certifying.certifyingBenchScenarios
          ]
            ++ [ test (g ++ "/" ++ name) ok [PlutusTx.toData expiration, PlutusTx.toData ctx]
               | (g, cases) <- Certifying.certifyingUnitCases
               , (name, ok, expiration, ctx) <- cases
               ]
      }
  , ValidatorSpec
      { vsName = "Vesting"
      , vsPlinth = programFromScript plinthVestingScript
      , vsPlutarch = programFromScript (compileNoTracing mkVestingValidator)
      , vsReturnsInteger = False
      , vsCases =
          [bench name [PlutusTx.toData ctx] | (name, ctx) <- Vesting.vestingBenchScenarios]
            ++ [ test (g ++ "/" ++ name) ok [PlutusTx.toData ctx]
               | (g, cases) <- Vesting.vestingUnitCases
               , (name, ok, ctx) <- cases
               ]
      }
  , ValidatorSpec
      { vsName = "Constitution"
      , vsPlinth = programFromScript plinthConstitutionScript
      , vsPlutarch = programFromScript (compileNoTracing mkConstitutionValidator)
      , vsReturnsInteger = False
      , vsCases =
          [ bench name [PlutusTx.toData config, PlutusTx.toData ctx]
          | (name, config, ctx) <- ConstitutionSorted.constitutionBenchScenarios
          ]
            ++ [ test (g ++ "/" ++ name) ok [PlutusTx.toData config, PlutusTx.toData ctx]
               | (g, cases) <- ConstitutionSorted.constitutionUnitCases
               , (name, ok, config, ctx) <- cases
               ]
      }
  , ValidatorSpec
      { vsName = "Crowdfund"
      , vsPlinth = programFromScript plinthCrowdfundScript
      , vsPlutarch = programFromScript (compileNoTracing mkCrowdfundValidator)
      , vsReturnsInteger = False
      , vsCases =
          [bench name [PlutusTx.toData ctx] | (name, ctx) <- Crowdfund.crowdfundBenchScenarios]
            ++ [ test (g ++ "/" ++ name) ok [PlutusTx.toData ctx]
               | (g, cases) <- Crowdfund.crowdfundUnitCases
               , (name, ok, ctx) <- cases
               ]
      }
  , ValidatorSpec
      { vsName = "Settings"
      , vsPlinth = programFromScript plinthSettingsScript
      , vsPlutarch = programFromScript (compileNoTracing mkSettingsValidator)
      , vsReturnsInteger = False
      , vsCases =
          [ bench name [PlutusTx.toData Settings.bootUtxoRef, PlutusTx.toData ctx]
          | (name, ctx) <- Settings.settingsBenchScenarios
          ]
            ++ [ test (g ++ "/" ++ name) ok [PlutusTx.toData Settings.bootUtxoRef, PlutusTx.toData ctx]
               | (g, cases) <- Settings.settingsUnitCases
               , (name, ok, ctx) <- cases
               ]
      }
  , ValidatorSpec
      { vsName = "Hydra"
      , vsPlinth = programFromScript plinthHeadScript
      , vsPlutarch = programFromScript (compileNoTracing mkHeadValidator)
      , vsReturnsInteger = False
      , vsCases =
          [bench name [PlutusTx.toData ctx] | (name, ctx) <- HydraHead.headBenchScenarios]
            ++ [test name ok [PlutusTx.toData ctx] | (name, ok, ctx) <- HydraHead.headUnitCases]
      }
  , ValidatorSpec
      { vsName = "ProgrammableLogicGlobal"
      , vsPlinth = programFromScript plinthProgrammableLogicGlobalScript
      , vsPlutarch = programFromScript (compileNoTracing mkProgrammableLogicGlobal)
      , vsReturnsInteger = False
      , vsCases =
          [ bench name [PlutusTx.toData ProgrammableLogicGlobal.protocolParamsCS, PlutusTx.toData ctx]
          | (name, ctx) <- ProgrammableLogicGlobal.globalBenchScenarios
          ]
            ++ [ test name ok [PlutusTx.toData ProgrammableLogicGlobal.protocolParamsCS, PlutusTx.toData ctx]
               | (name, ok, ctx) <- ProgrammableLogicGlobal.globalUnitCases
               ]
      }
  , ValidatorSpec
      { vsName = "Sample"
      , vsPlinth = programFromCompiledCode SamplePlinth.netWithdrawUPLC
      , vsPlutarch = programFromScript SamplePlutarch.netWithdrawUPLC
      , vsReturnsInteger = True
      , vsCases =
          [ (bench name [PlutusTx.toData w]) {csReference = Just (SamplePlinth.netWithdraw w)}
          | (name, w) <- sampleWithdrawals
          ]
      }
  ]

-- ============================================================================
-- Sample inputs
-- ============================================================================

{- | A deterministic set of 'Withdraw' trees. Depth counts levels of
constructors, so @Amount n@ has depth 1.
-}
sampleWithdrawals :: [(String, Withdraw)]
sampleWithdrawals =
  [ ("amount: depth 1", Amount 42)
  , ("amount: big integer (depth 1)", Amount (2 ^ (255 :: Integer)))
  , ("amount: negative (depth 1)", Amount (-1_234_567))
  , ("joint: depth 2", Joint (Amount 17) (Amount 25))
  , ("deduct: depth 2", Deduct 30 (Amount 100))
  , ("mixed: depth 3", Joint (Deduct 5 (Amount 50)) (Joint (Amount 1) (Amount 2)))
  , ("deduct chain: depth 8", foldr Deduct (Amount 1_000) [1 .. 7])
  , ("joint left spine: depth 8", jointSpine 8)
  , ("full joint tree: depth 5", fullJoint 1 5)
  , ("full joint tree: depth 8", fullJoint 1 8)
  , ("full mixed tree: depth 8", fullMixed 1 8)
  , ("big integer mixed tree: depth 6", bigMixed 1 6)
  ]
  where
    jointSpine :: Int -> Withdraw
    jointSpine d
      | d <= 1 = Amount 1
      | otherwise = Joint (jointSpine (d - 1)) (Amount (fromIntegral d * 11))

    -- Complete binary tree of Joint nodes over distinct leaves.
    fullJoint :: Integer -> Int -> Withdraw
    fullJoint seed d
      | d <= 1 = Amount seed
      | otherwise = Joint (fullJoint (2 * seed) (d - 1)) (fullJoint (2 * seed + 1) (d - 1))

    -- Alternates Joint and Deduct levels.
    fullMixed :: Integer -> Int -> Withdraw
    fullMixed seed d
      | d <= 1 = Amount (seed * 1_000)
      | even d = Joint (fullMixed (2 * seed) (d - 1)) (fullMixed (2 * seed + 1) (d - 1))
      | otherwise = Deduct seed (fullMixed (seed + 1) (d - 1))

    -- Like 'fullMixed' but with integers far beyond 64 bits.
    bigMixed :: Integer -> Int -> Withdraw
    bigMixed seed d
      | d <= 1 = Amount (seed * 2 ^ (128 :: Integer) + 3 ^ (40 :: Integer))
      | even d = Joint (bigMixed (2 * seed) (d - 1)) (bigMixed (2 * seed + 1) (d - 1))
      | otherwise = Deduct (seed * 10 ^ (30 :: Integer)) (bigMixed (seed + 1) (d - 1))
