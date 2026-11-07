{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-missing-export-lists #-}
{-# OPTIONS_GHC -Wno-missing-import-lists #-}

module Main where

import Certifying.Contracts.Certifying (mkCertifyingValidator)
import Certifying.Contracts.CertifyingPlinth (plinthCertifyingScript)
import Certifying.Test.Certifying qualified as Certifying
import Codec.Extras.SerialiseViaFlat (SerialiseViaFlat (..))
import Codec.Serialise (serialise)
import Constitution.Contracts.ConstitutionSorted (mkConstitutionValidator)
import Constitution.Contracts.ConstitutionSortedPlinth (plinthConstitutionScript)
import Constitution.Test.ConstitutionSorted qualified as ConstitutionSorted
import Constitution.Types.ConstitutionConfig (ParamValue)
import Control.Lens (traverseOf)
import Crowdfund.Contracts.Crowdfund (mkCrowdfundValidator)
import Crowdfund.Contracts.CrowdfundPlinth (plinthCrowdfundScript)
import Crowdfund.Test.Crowdfund qualified as Crowdfund
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isRight)
import Hydra.Contracts.Head (mkHeadValidator)
import Hydra.Contracts.HeadPlinth (plinthHeadScript)
import Hydra.Test.Head qualified as HydraHead
import Plutarch.Evaluate (applyArguments, evalScript)
import Plutarch.Internal.Term (Config (NoTracing), Script, Term, compile)
import Plutarch.Script (Script (..))
import PlutusCore qualified as PLC
import PlutusCore.DeBruijn
import PlutusCore.Pretty
import PlutusLedgerApi.V3
import PlutusPrelude (unsafeFromRight)
import PlutusTx qualified
import ProgrammableTokens.Test.ProgrammableLogicGlobal qualified as ProgrammableLogicGlobal
import Settings.Contracts.Settings (mkSettingsValidator)
import Settings.Contracts.SettingsPlinth (plinthSettingsScript)
import Settings.Test.Settings qualified as Settings
import SmartTokens.Contracts.ProgrammableLogicBase (mkProgrammableLogicGlobal)
import SmartTokens.Contracts.ProgrammableLogicBasePlinth (plinthProgrammableLogicGlobalScript)
import Text.Printf (printf)
import UntypedPlutusCore qualified as UPLC
import Vesting.Contracts.Vesting (mkVestingValidator)
import Vesting.Contracts.VestingPlinth (plinthVestingScript)
import Vesting.Test.Vesting qualified as Vesting
import Voting.Contracts.Voting (mkVotingValidator)
import Voting.Contracts.VotingPlinth (plinthVotingScript)
import Voting.Test.Voting qualified as Voting

plutarchHeadScript :: Script
plutarchHeadScript = compileNoTracing mkHeadValidator

plutarchConstitutionScript :: Script
plutarchConstitutionScript = compileNoTracing mkConstitutionValidator

plutarchCrowdfundScript :: Script
plutarchCrowdfundScript = compileNoTracing mkCrowdfundValidator

plutarchSettingsScript :: Script
plutarchSettingsScript = compileNoTracing mkSettingsValidator

plutarchVestingScript :: Script
plutarchVestingScript = compileNoTracing mkVestingValidator

plutarchCertifyingScript :: Script
plutarchCertifyingScript = compileNoTracing mkCertifyingValidator

plutarchVotingScript :: Script
plutarchVotingScript = compileNoTracing mkVotingValidator

scriptSize :: Script -> Int
scriptSize (Script prog) = fromIntegral $ LBS.length $ serialise $ SerialiseViaFlat $ UPLC.UnrestrictedProgram prog

printSizes :: String -> Script -> Script -> IO ()
printSizes _name plutarchS plinthS = do
  let pSize = scriptSize plutarchS
      tSize = scriptSize plinthS
      sizeRatio = (fromIntegral tSize :: Double) / fromIntegral pSize
  printf "  Script size: Plutarch = %d bytes, Plinth = %d bytes (%.2fx)\n" pSize tSize sizeRatio

main :: IO ()
main = do
  putStrLn ""
  putStrLn "CIP-143 ProgrammableLogicGlobal -- Execution Cost Comparison"
  printSizes "ProgrammableLogicGlobal" plutarchScript plinthScript
  putStrLn (replicate 140 '=')
  printHeader
  mapM_ runComparison ProgrammableLogicGlobal.globalBenchScenarios
  putStrLn (replicate 140 '=')

  putStrLn ""
  putStrLn "Hydra Head Validator -- Execution Cost Comparison"
  printSizes "HeadValidator" plutarchHeadScript plinthHeadScript
  putStrLn (replicate 140 '=')
  printHeader
  mapM_ (runHeadComparison plutarchHeadScript plinthHeadScript) HydraHead.headBenchScenarios
  putStrLn (replicate 140 '=')

  putStrLn ""
  putStrLn "Constitution Sorted Validator -- Execution Cost Comparison"
  printSizes "ConstitutionSorted" plutarchConstitutionScript plinthConstitutionScript
  putStrLn (replicate 140 '=')
  printHeader
  mapM_
    (runConstitutionComparison plutarchConstitutionScript plinthConstitutionScript)
    ConstitutionSorted.constitutionBenchScenarios
  putStrLn (replicate 140 '=')

  putStrLn ""
  putStrLn "Crowdfund Validator -- Execution Cost Comparison"
  printSizes "Crowdfund" plutarchCrowdfundScript plinthCrowdfundScript
  putStrLn (replicate 140 '=')
  printHeader
  mapM_
    (runCrowdfundComparison plutarchCrowdfundScript plinthCrowdfundScript)
    Crowdfund.crowdfundBenchScenarios
  putStrLn (replicate 140 '=')

  putStrLn ""
  putStrLn "Settings Validator -- Execution Cost Comparison"
  printSizes "Settings" plutarchSettingsScript plinthSettingsScript
  putStrLn (replicate 140 '=')
  printHeader
  mapM_
    (runSettingsComparison plutarchSettingsScript plinthSettingsScript)
    Settings.settingsBenchScenarios
  putStrLn (replicate 140 '=')

  putStrLn ""
  putStrLn "Vesting Validator -- Execution Cost Comparison"
  printSizes "Vesting" plutarchVestingScript plinthVestingScript
  putStrLn (replicate 140 '=')
  printHeader
  mapM_ (runVestingComparison plutarchVestingScript plinthVestingScript) Vesting.vestingBenchScenarios
  putStrLn (replicate 140 '=')

  putStrLn ""
  putStrLn "Certifying Validator -- Execution Cost Comparison"
  printSizes "Certifying" plutarchCertifyingScript plinthCertifyingScript
  putStrLn (replicate 140 '=')
  printHeader
  mapM_
    (runCertifyingComparison plutarchCertifyingScript plinthCertifyingScript)
    Certifying.certifyingBenchScenarios
  putStrLn (replicate 140 '=')

  putStrLn ""
  putStrLn "Voting Validator -- Execution Cost Comparison"
  printSizes "Voting" plutarchVotingScript plinthVotingScript
  putStrLn (replicate 140 '=')
  printHeader
  mapM_ (runVotingComparison plutarchVotingScript plinthVotingScript) Voting.votingBenchScenarios
  putStrLn (replicate 140 '=')

renderScript :: Script -> String
renderScript = render . prettyReadable . ndb2name . db2ndb . unScript

db2ndb
  :: UPLC.Program UPLC.DeBruijn UPLC.DefaultUni UPLC.DefaultFun ()
  -> UPLC.Program UPLC.NamedDeBruijn UPLC.DefaultUni UPLC.DefaultFun ()
db2ndb = UPLC.programMapNames fakeNameDeBruijn

ndb2name
  :: UPLC.Program UPLC.NamedDeBruijn UPLC.DefaultUni UPLC.DefaultFun ()
  -> UPLC.Program UPLC.Name UPLC.DefaultUni UPLC.DefaultFun ()
ndb2name =
  unsafeFromRight @PLC.FreeVariableError
    . PLC.runQuoteT
    . traverseOf UPLC.progTerm UPLC.unDeBruijnTerm

printHeader :: IO ()
printHeader = do
  printf
    "%-40s | %-12s %-12s %-4s | %-12s %-12s %-4s | %-10s %-10s\n"
    ("Scenario" :: String)
    ("CPU" :: String)
    ("Mem" :: String)
    ("" :: String)
    ("CPU" :: String)
    ("Mem" :: String)
    ("" :: String)
    ("CPU" :: String)
    ("Mem" :: String)
  printf
    "%-40s | %-12s %-12s %-4s | %-12s %-12s %-4s | %-10s %-10s\n"
    ("" :: String)
    ("Plutarch" :: String)
    ("" :: String)
    ("" :: String)
    ("Plinth" :: String)
    ("" :: String)
    ("" :: String)
    ("ratio" :: String)
    ("ratio" :: String)
  putStrLn (replicate 140 '-')

evalWith :: Script -> ScriptContext -> (Bool, String, String)
evalWith script ctx =
  let applied = applyArguments script [PlutusTx.toData ProgrammableLogicGlobal.protocolParamsCS, PlutusTx.toData ctx]
      (res, ExBudget (ExCPU cpu) (ExMemory mem), _logs) = evalScript applied
      ok = isRight res
   in (ok, show cpu, show mem)

ratioStr :: String -> String -> String
ratioStr a b = case (reads a, reads b) of
  ([(va, _)], [(vb, _)]) | va > (0 :: Double) -> printf "%.2fx" (vb / va)
  _ -> "N/A"

runComparison :: (String, ScriptContext) -> IO ()
runComparison (name, ctx) = do
  let (okP, cpuP, memP) = evalWith plutarchScript ctx
      (okT, cpuT, memT) = evalWith plinthScript ctx
      statusP = if okP then "OK" else "FAIL" :: String
      statusT = if okT then "OK" else "FAIL" :: String
      cpuR = ratioStr cpuP cpuT
      memR = ratioStr memP memT
  printf
    "%-40s | %12s %12s %-4s | %12s %12s %-4s | %-10s %-10s\n"
    name
    cpuP
    memP
    statusP
    cpuT
    memT
    statusT
    cpuR
    memR

evalHeadWith :: Script -> ScriptContext -> (Bool, String, String)
evalHeadWith script ctx =
  let applied = applyArguments script [PlutusTx.toData ctx]
      (res, ExBudget (ExCPU cpu) (ExMemory mem), _logs) = evalScript applied
      ok = isRight res
   in (ok, show cpu, show mem)

evalConstitutionWith :: Script -> [(Integer, ParamValue)] -> ScriptContext -> (Bool, String, String)
evalConstitutionWith script config ctx =
  let applied = applyArguments script [PlutusTx.toData config, PlutusTx.toData ctx]
      (res, ExBudget (ExCPU cpu) (ExMemory mem), _logs) = evalScript applied
      ok = isRight res
   in (ok, show cpu, show mem)

runConstitutionComparison
  :: Script -> Script -> (String, [(Integer, ParamValue)], ScriptContext) -> IO ()
runConstitutionComparison plutarchS plinthS (name, config, ctx) = do
  let (okP, cpuP, memP) = evalConstitutionWith plutarchS config ctx
      (okT, cpuT, memT) = evalConstitutionWith plinthS config ctx
      statusP = if okP then "OK" else "FAIL" :: String
      statusT = if okT then "OK" else "FAIL" :: String
      cpuR = ratioStr cpuP cpuT
      memR = ratioStr memP memT
  printf
    "%-40s | %12s %12s %-4s | %12s %12s %-4s | %-10s %-10s\n"
    name
    cpuP
    memP
    statusP
    cpuT
    memT
    statusT
    cpuR
    memR

runHeadComparison :: Script -> Script -> (String, ScriptContext) -> IO ()
runHeadComparison plutarchS plinthS (name, ctx) = do
  let (okP, cpuP, memP) = evalHeadWith plutarchS ctx
      (okT, cpuT, memT) = evalHeadWith plinthS ctx
      statusP = if okP then "OK" else "FAIL" :: String
      statusT = if okT then "OK" else "FAIL" :: String
      cpuR = ratioStr cpuP cpuT
      memR = ratioStr memP memT
  printf
    "%-40s | %12s %12s %-4s | %12s %12s %-4s | %-10s %-10s\n"
    name
    cpuP
    memP
    statusP
    cpuT
    memT
    statusT
    cpuR
    memR

runCrowdfundComparison :: Script -> Script -> (String, ScriptContext) -> IO ()
runCrowdfundComparison plutarchS plinthS (name, ctx) = do
  let (okP, cpuP, memP) = evalHeadWith plutarchS ctx
      (okT, cpuT, memT) = evalHeadWith plinthS ctx
      statusP = if okP then "OK" else "FAIL" :: String
      statusT = if okT then "OK" else "FAIL" :: String
      cpuR = ratioStr cpuP cpuT
      memR = ratioStr memP memT
  printf
    "%-40s | %12s %12s %-4s | %12s %12s %-4s | %-10s %-10s\n"
    name
    cpuP
    memP
    statusP
    cpuT
    memT
    statusT
    cpuR
    memR

settingsBootUtxoRef :: TxOutRef
settingsBootUtxoRef = Settings.bootUtxoRef

evalSettingsWith :: Script -> ScriptContext -> (Bool, String, String)
evalSettingsWith script ctx =
  let applied = applyArguments script [PlutusTx.toData settingsBootUtxoRef, PlutusTx.toData ctx]
      (res, ExBudget (ExCPU cpu) (ExMemory mem), _logs) = evalScript applied
      ok = isRight res
   in (ok, show cpu, show mem)

runSettingsComparison :: Script -> Script -> (String, ScriptContext) -> IO ()
runSettingsComparison plutarchS plinthS (name, ctx) = do
  let (okP, cpuP, memP) = evalSettingsWith plutarchS ctx
      (okT, cpuT, memT) = evalSettingsWith plinthS ctx
      statusP = if okP then "OK" else "FAIL" :: String
      statusT = if okT then "OK" else "FAIL" :: String
      cpuR = ratioStr cpuP cpuT
      memR = ratioStr memP memT
  printf
    "%-40s | %12s %12s %-4s | %12s %12s %-4s | %-10s %-10s\n"
    name
    cpuP
    memP
    statusP
    cpuT
    memT
    statusT
    cpuR
    memR

runVestingComparison :: Script -> Script -> (String, ScriptContext) -> IO ()
runVestingComparison plutarchS plinthS (name, ctx) = do
  let (okP, cpuP, memP) = evalHeadWith plutarchS ctx
      (okT, cpuT, memT) = evalHeadWith plinthS ctx
      statusP = if okP then "OK" else "FAIL" :: String
      statusT = if okT then "OK" else "FAIL" :: String
      cpuR = ratioStr cpuP cpuT
      memR = ratioStr memP memT
  printf
    "%-40s | %12s %12s %-4s | %12s %12s %-4s | %-10s %-10s\n"
    name
    cpuP
    memP
    statusP
    cpuT
    memT
    statusT
    cpuR
    memR

evalCertifyingWith :: Script -> Integer -> ScriptContext -> (Bool, String, String)
evalCertifyingWith script expiration ctx =
  let applied = applyArguments script [PlutusTx.toData expiration, PlutusTx.toData ctx]
      (res, ExBudget (ExCPU cpu) (ExMemory mem), _logs) = evalScript applied
      ok = isRight res
   in (ok, show cpu, show mem)

runCertifyingComparison :: Script -> Script -> (String, Integer, ScriptContext) -> IO ()
runCertifyingComparison plutarchS plinthS (name, expiration, ctx) = do
  let (okP, cpuP, memP) = evalCertifyingWith plutarchS expiration ctx
      (okT, cpuT, memT) = evalCertifyingWith plinthS expiration ctx
      statusP = if okP then "OK" else "FAIL" :: String
      statusT = if okT then "OK" else "FAIL" :: String
      cpuR = ratioStr cpuP cpuT
      memR = ratioStr memP memT
  printf
    "%-40s | %12s %12s %-4s | %12s %12s %-4s | %-10s %-10s\n"
    name
    cpuP
    memP
    statusP
    cpuT
    memT
    statusT
    cpuR
    memR

evalVotingWith :: Script -> CurrencySymbol -> TokenName -> ScriptContext -> (Bool, String, String)
evalVotingWith script cs tn ctx =
  let applied = applyArguments script [PlutusTx.toData cs, PlutusTx.toData tn, PlutusTx.toData ctx]
      (res, ExBudget (ExCPU cpu) (ExMemory mem), _logs) = evalScript applied
      ok = isRight res
   in (ok, show cpu, show mem)

runVotingComparison
  :: Script -> Script -> (String, CurrencySymbol, TokenName, ScriptContext) -> IO ()
runVotingComparison plutarchS plinthS (name, cs, tn, ctx) = do
  let (okP, cpuP, memP) = evalVotingWith plutarchS cs tn ctx
      (okT, cpuT, memT) = evalVotingWith plinthS cs tn ctx
      statusP = if okP then "OK" else "FAIL" :: String
      statusT = if okT then "OK" else "FAIL" :: String
      cpuR = ratioStr cpuP cpuT
      memR = ratioStr memP memT
  printf
    "%-40s | %12s %12s %-4s | %12s %12s %-4s | %-10s %-10s\n"
    name
    cpuP
    memP
    statusP
    cpuT
    memT
    statusT
    cpuR
    memR

plutarchScript :: Script
plutarchScript = compileNoTracing mkProgrammableLogicGlobal

plinthScript :: Script
plinthScript = plinthProgrammableLogicGlobalScript

compileNoTracing :: (forall s. Term s a) -> Script
compileNoTracing term =
  either (error . ("compile failed: " <>) . show) id (compile NoTracing term)
