{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- | Batch evaluation of arbitrary (program, arguments) jobs on the plutus-core
CEK machine, for differential testing of compilers.

Input: one job per line, three tab-separated fields

  ID <TAB> PROGRAM <TAB> ARGS

or, to avoid repeating large programs and arguments, definition lines:
@P <TAB> PID <TAB> PROGRAM@ defines a program, @A <TAB> ARGS@ sets the
current arguments, and @J <TAB> ID <TAB> PID@ evaluates program PID on the
current arguments.

where PROGRAM is a flat-encoded UPLC program in hex and ARGS is a
comma-separated (possibly empty) list of arguments, each either
@d:<hex>@ (a CBOR-encoded 'Data', applied as a constant), @i:<decimal>@ (an
integer constant), @b:<hex>@ (a bytestring constant) or @t:<hex>@ (a
flat-encoded closed program whose body is applied as a term).

Output: one line per job, six tab-separated fields

  ID <TAB> OUTCOME <TAB> CPU <TAB> MEM <TAB> RESULT <TAB> TRACES

OUTCOME is OK (halted), FAIL (evaluation error), BUDGET (the budget ran
out: treated as divergence) or BAD (undecodable job). RESULT is a canonical
rendering of the value for OK (constants in full, constructors with their
fields, @<fn>@ for lambdas and partial builtin applications, @<delay>@ for
delays), and the error class for FAIL. TRACES lists the emitted trace
messages, each UTF-8 hex encoded, separated by commas. CPU and MEM are the
spent budget.
-}
module CrossBench.Batch (
  BatchOptions (..),
  defaultBatchOptions,
  runBatch,
  canonicalTerm,
) where

import Control.Exception (SomeException, evaluate, try)
import Data.ByteString.Char8 qualified as BS8
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (isInfixOf)
import Data.Map.Strict qualified as Map
import Data.Text.Encoding qualified as TE
import PlutusCore qualified as PLC
import PlutusCore.Default (BuiltinSemanticsVariant (DefaultFunSemanticsVariantA, DefaultFunSemanticsVariantB, DefaultFunSemanticsVariantC, DefaultFunSemanticsVariantD, DefaultFunSemanticsVariantE), DefaultFun, DefaultUni)
import PlutusCore.Evaluation.Machine.ExBudget (ExBudget (ExBudget), ExRestrictingBudget (ExRestrictingBudget))
import PlutusCore.Evaluation.Machine.ExBudgetingDefaults (defaultCekParametersForVariant)
import PlutusCore.Evaluation.Machine.ExMemory (ExCPU (ExCPU), ExMemory (ExMemory))
import PlutusCore.Pretty (prettyPlcClassic, render)
import System.IO (hFlush, hIsEOF, stdin, stdout)
import UntypedPlutusCore qualified as UPLC
import UntypedPlutusCore.Evaluation.Machine.Cek qualified as Cek

import CrossBench.Eval (decodeFlat, decodeHex, deserialiseData, encodeHex)

data BatchOptions = BatchOptions
  { boVariant :: String
  , boCpu :: Integer
  , boMem :: Integer
  }

defaultBatchOptions :: BatchOptions
defaultBatchOptions = BatchOptions "E" 100000000000 1000000000

type NTerm = UPLC.Term UPLC.NamedDeBruijn DefaultUni DefaultFun ()

type DTerm = UPLC.Term UPLC.DeBruijn DefaultUni DefaultFun ()

semantics :: String -> Either String (BuiltinSemanticsVariant DefaultFun)
semantics v = case v of
  "A" -> Right DefaultFunSemanticsVariantA
  "B" -> Right DefaultFunSemanticsVariantB
  "C" -> Right DefaultFunSemanticsVariantC
  "D" -> Right DefaultFunSemanticsVariantD
  "E" -> Right DefaultFunSemanticsVariantE
  _ -> Left ("unknown semantics variant " ++ v)

runBatch :: BatchOptions -> IO ()
runBatch opts = do
  variant <- either fail pure (semantics (boVariant opts))
  let params = defaultCekParametersForVariant variant
  programs <- newIORef (Map.empty :: Map.Map String (Either String DTerm))
  current <- newIORef (Right [] :: Either String [DTerm])
  let loop = do
        eof <- hIsEOF stdin
        if eof
          then hFlush stdout
          else do
            line <- BS8.getLine
            case splitTab (BS8.unpack line) of
              ["P", pid, hex] ->
                modifyIORef' programs (Map.insert pid (decodeProgram hex))
              ["A", args] -> writeIORef current (decodeArgs args)
              ["A"] -> writeIORef current (Right [])
              ["J", jobId, pid] -> do
                prog <- Map.lookup pid <$> readIORef programs
                args <- readIORef current
                let term = do
                      body <- maybe (Left ("unknown program " ++ pid)) id prog
                      foldl (UPLC.Apply ()) body <$> args
                emit jobId term
              [jobId, prog, args] ->
                emit jobId (decodeProgram prog >>= \body -> foldl (UPLC.Apply ()) body <$> decodeArgs args)
              [""] -> pure ()
              fields -> putStrLn (headOr "?" fields ++ "\tBAD\t0\t0\tunexpected line\t")
            loop
      emit jobId term = do
        result <- try (evaluate (forceString (either (\err -> "BAD\t0\t0\t" ++ clean err ++ "\t") (runTerm params) term)))
        putStrLn $ case result of
          Right s -> jobId ++ "\t" ++ s
          Left (e :: SomeException) -> jobId ++ "\tBAD\t0\t0\t" ++ clean (show e) ++ "\t"
  loop
  where
    runTerm params term =
          let named = UPLC.termMapNames UPLC.fakeNameDeBruijn term
              Cek.CekReport res (Cek.RestrictingSt (ExRestrictingBudget (ExBudget (ExCPU cpuLeft) (ExMemory memLeft)))) logs =
                Cek.runCekDeBruijn params (Cek.restricting (ExRestrictingBudget (ExBudget (ExCPU (fromIntegral (boCpu opts))) (ExMemory (fromIntegral (boMem opts)))))) Cek.logEmitter named
              cpu = boCpu opts - read (show cpuLeft)
              mem = boMem opts - read (show memLeft)
              traces = joinComma (map (encodeHex . TE.encodeUtf8) logs)
              (outcome, rendered) = case res of
                Cek.CekFailure err ->
                  let msg = show err
                   in if "OutOfEx" `isInfixOf` msg then ("BUDGET", "budget") else ("FAIL", failureClass msg)
                Cek.CekSuccessConstant c -> ("OK", canonicalTerm (UPLC.Constant () c))
                Cek.CekSuccessNonConstant t -> ("OK", canonicalTerm t)
           in outcome ++ "\t" ++ show cpu ++ "\t" ++ show mem ++ "\t" ++ clean rendered ++ "\t" ++ traces

forceString :: String -> String
forceString s = length s `seq` s

headOr :: a -> [a] -> a
headOr d [] = d
headOr _ (x : _) = x

decodeProgram :: String -> Either String DTerm
decodeProgram hex = do
  UPLC.Program _ _ body <- decodeHex hex >>= decodeFlat
  pure body

decodeArgs :: String -> Either String [DTerm]
decodeArgs argsField = mapM decodeArg (filter (not . null) (splitComma argsField))
  where
    decodeArg ('d' : ':' : hex) = do
      d <- decodeHex hex >>= deserialiseData
      pure (UPLC.Constant () (PLC.someValue d))
    decodeArg ('t' : ':' : hex) = decodeProgram hex
    decodeArg ('i' : ':' : digits) = case reads digits of
      [(n, "")] -> Right (UPLC.Constant () (PLC.someValue (n :: Integer)))
      _ -> Left "bad integer argument"
    decodeArg ('b' : ':' : hex) = UPLC.Constant () . PLC.someValue <$> decodeHex hex
    decodeArg other = Left ("bad argument " ++ take 20 other)

{- | A canonical rendering of a CEK result, independent of how a compiler
represents functions: constants and constructor trees are rendered in full,
every lambda or partial builtin application as @<fn>@, every delay as
@<delay>@.
-}
canonicalTerm :: NTerm -> String
canonicalTerm t = case t of
  UPLC.Constant {} -> render (prettyPlcClassic t)
  UPLC.Constr _ i fields -> "(constr " ++ show i ++ concatMap ((' ' :) . canonicalTerm) fields ++ ")"
  UPLC.LamAbs {} -> "<fn>"
  UPLC.Delay {} -> "<delay>"
  UPLC.Builtin {} -> "<fn>"
  UPLC.Apply {} | builtinHead t -> "<fn>"
  UPLC.Force {} | builtinHead t -> "<fn>"
  _ -> "<term>"
  where
    builtinHead (UPLC.Builtin {}) = True
    builtinHead (UPLC.Apply _ f _) = builtinHead f
    builtinHead (UPLC.Force _ f) = builtinHead f
    builtinHead _ = False

-- | The class of an evaluation failure, without budget or term details.
failureClass :: String -> String
failureClass msg
  | "OpenTermEvaluated" `isInfixOf` msg = "open-term"
  | "explicit use of 'error'" `isInfixOf` msg = "error"
  | otherwise = take 120 (unwords (words msg))

clean :: String -> String
clean = map (\c -> if c == '\t' || c == '\n' || c == '\r' then ' ' else c)

splitTab :: String -> [String]
splitTab = splitOnChar '\t'

splitComma :: String -> [String]
splitComma = splitOnChar ','

splitOnChar :: Char -> String -> [String]
splitOnChar sep s = case break (== sep) s of
  (a, []) -> [a]
  (a, _ : rest) -> a : splitOnChar sep rest

joinComma :: [String] -> String
joinComma [] = ""
joinComma (x : xs) = x ++ concatMap (',' :) xs
