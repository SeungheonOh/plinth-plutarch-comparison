{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- | Script encoding and evaluation for the cross-language benchmark.

Every script, whichever compiler produced it, goes through the same path:
flat-decoded into a DeBruijn UPLC program, applied to its 'Data' arguments as
constants, and run on the plutus-core CEK machine in counting mode (no budget
limit; the spent budget is measured).
-}
module CrossBench.Eval (
  Program,
  CostVariant (..),
  allCostVariants,
  costVariantName,
  Outcome (..),
  EvalResult (..),
  evaluate,
  programFromScript,
  programFromCompiledCode,
  encodeFlat,
  decodeFlat,
  cborWrap,
  unwrapCbor,
  encodeHex,
  decodeHex,
  serialiseData,
  deserialiseData,
  tallyReport,
  prettyProgram,
  parseProgramText,
) where

import Data.Text qualified as T
import PlutusCore.Error (ParserErrorBundle)
import PlutusCore.Pretty (prettyPlcClassic)
import UntypedPlutusCore.Parser qualified as UPLCParser

import Control.Monad.Except (runExcept)
import PlutusCore.Pretty (display, render)
import PlutusCore.Quote (runQuoteT)

import Codec.Serialise (deserialiseOrFail, serialise)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (chr, digitToInt, isHexDigit, ord)
import Data.Word (Word8)
import Plutarch.Script (Script (..))
import PlutusCore qualified as PLC
import PlutusCore.Data (Data)
import PlutusCore.Default (BuiltinSemanticsVariant (DefaultFunSemanticsVariantC, DefaultFunSemanticsVariantE), DefaultFun, DefaultUni (DefaultUniInteger))
import PlutusCore.Evaluation.Machine.ExBudget (ExBudget (ExBudget))
import PlutusCore.Evaluation.Machine.ExBudgetingDefaults (defaultCekParametersForVariant)
import PlutusCore.Evaluation.Machine.ExMemory (ExCPU (ExCPU), ExMemory (ExMemory))
import PlutusCore.Flat qualified as Flat
import PlutusTx.Code (CompiledCode, getPlcNoAnn)
import UntypedPlutusCore qualified as UPLC
import UntypedPlutusCore.Evaluation.Machine.Cek qualified as Cek

type Program = UPLC.Program UPLC.DeBruijn DefaultUni DefaultFun ()

{- | The two PlutusV3 cost-model variants the benchmark evaluates under.

The ledger (plutus-ledger-api 1.65, "PlutusLedgerApi.MachineParameters") runs
PlutusV3 scripts with builtin semantics variant C before the van Rossem
protocol version and with variant E from it onwards. Each variant here is
evaluated with exactly the machine parameters plutus-core 1.65 ships for it:

  * C: @defaultCekParametersForVariant DefaultFunSemanticsVariantC@, i.e.
       builtin semantics 'DefaultFunSemanticsVariantC' with @cekCostModelVariantC@
       (builtinCostModelC.json + cekMachineCostsC.json);
  * E: @defaultCekParametersForVariant DefaultFunSemanticsVariantE@, i.e.
       builtin semantics 'DefaultFunSemanticsVariantE' with @cekCostModelVariantE@
       (builtinCostModelE.json + cekMachineCostsE.json).

Both come from "PlutusCore.Evaluation.Machine.ExBudgetingDefaults".
-}
data CostVariant = VariantC | VariantE
  deriving stock (Eq, Ord, Show, Enum, Bounded)

allCostVariants :: [CostVariant]
allCostVariants = [minBound .. maxBound]

costVariantName :: CostVariant -> String
costVariantName VariantC = "C"
costVariantName VariantE = "E"

semanticsVariant :: CostVariant -> BuiltinSemanticsVariant DefaultFun
semanticsVariant VariantC = DefaultFunSemanticsVariantC
semanticsVariant VariantE = DefaultFunSemanticsVariantE

-- | What a script evaluation produced.
data Outcome
  = -- | Evaluation failed (an @error@, a builtin failure, an ill-formed term, ...).
    Failed String
  | -- | Evaluation succeeded with an integer constant.
    SucceededInteger Integer
  | -- | Evaluation succeeded with some other value.
    Succeeded
  deriving stock (Eq, Show)

data EvalResult = EvalResult
  { erOutcome :: Outcome
  , erCpu :: Integer
  , erMem :: Integer
  }
  deriving stock (Show)

-- | Apply a program to 'Data' constants and evaluate it with the CEK machine.
evaluate :: CostVariant -> Program -> [Data] -> EvalResult
evaluate variant (UPLC.Program _ _ body) args =
  let applied = foldl (\f a -> UPLC.Apply () f (UPLC.Constant () (PLC.someValue a))) body args
      term = UPLC.termMapNames UPLC.fakeNameDeBruijn applied
      params = defaultCekParametersForVariant (semanticsVariant variant)
      Cek.CekReport res (Cek.CountingSt (ExBudget (ExCPU cpu) (ExMemory mem))) _logs =
        Cek.runCekDeBruijn params Cek.counting Cek.noEmitter term
      outcome = case res of
        Cek.CekFailure err -> Failed (show err)
        Cek.CekSuccessConstant (PLC.Some (PLC.ValueOf DefaultUniInteger n)) -> SucceededInteger n
        Cek.CekSuccessConstant _ -> Succeeded
        Cek.CekSuccessNonConstant _ -> Succeeded
   in EvalResult outcome (read (show cpu)) (read (show mem))

programFromScript :: Script -> Program
programFromScript = unScript

-- | The same conversion the Plinth contract modules use for their 'Script's.
programFromCompiledCode :: CompiledCode a -> Program
programFromCompiledCode code =
  let UPLC.Program ann ver body = getPlcNoAnn code
   in UPLC.Program ann ver (UPLC.termMapNames UPLC.unNameDeBruijn body)

encodeFlat :: Program -> BS.ByteString
encodeFlat = Flat.flat . UPLC.UnrestrictedProgram

decodeFlat :: BS.ByteString -> Either String Program
decodeFlat bs = case Flat.unflat bs of
  Left err -> Left ("flat decoding failed: " ++ show err)
  Right (UPLC.UnrestrictedProgram p) -> Right p

-- | Wrap flat bytes in a CBOR byte string, as a serialised script sits on chain.
cborWrap :: BS.ByteString -> LBS.ByteString
cborWrap = serialise

{- | Strip CBOR byte-string wrappers (any number of them). A flat-encoded
program starts with its version (major version 1 encodes as byte 0x01), while a
CBOR byte string starts with a byte in 0x40..0x5f, so the two cannot be
confused.
-}
unwrapCbor :: BS.ByteString -> Either String BS.ByteString
unwrapCbor bs = case BS.uncons bs of
  Just (b, _)
    | b >= 0x40 && b <= 0x5f -> case deserialiseOrFail (LBS.fromStrict bs) of
        Left err -> Left ("CBOR decoding failed: " ++ show err)
        Right inner -> unwrapCbor inner
  _ -> Right bs

encodeHex :: BS.ByteString -> String
encodeHex = concatMap byte . BS.unpack
  where
    byte w = [nibble (w `shiftR` 4), nibble (w .&. 0x0f)]
    nibble n
      | n < 10 = chr (ord '0' + fromIntegral n)
      | otherwise = chr (ord 'a' + fromIntegral n - 10)

decodeHex :: String -> Either String BS.ByteString
decodeHex str0 = BS.pack <$> go (strip str0)
  where
    strip s = case filter (`notElem` (" \t\r\n" :: String)) s of
      '0' : x : rest | x `elem` ("xX" :: String) -> rest
      s' -> s'
    go [] = Right []
    go (a : b : rest)
      | isHexDigit a && isHexDigit b = (toByte a b :) <$> go rest
    go _ = Left "invalid hex string"
    toByte :: Char -> Char -> Word8
    toByte a b = fromIntegral (digitToInt a `shiftL` 4 .|. digitToInt b)

serialiseData :: Data -> BS.ByteString
serialiseData = LBS.toStrict . serialise

deserialiseData :: BS.ByteString -> Either String Data
deserialiseData bs = case deserialiseOrFail (LBS.fromStrict bs) of
  Left err -> Left ("Data CBOR decoding failed: " ++ show err)
  Right d -> Right d

-- | Evaluate like 'evaluate', but in tallying mode, and render the per-step and
-- per-builtin cost breakdown.
tallyReport :: CostVariant -> Program -> [Data] -> String
tallyReport variant (UPLC.Program _ _ body) args =
  let applied = foldl (\f a -> UPLC.Apply () f (UPLC.Constant () (PLC.someValue a))) body args
      term = UPLC.termMapNames UPLC.fakeNameDeBruijn applied
      params = defaultCekParametersForVariant (semanticsVariant variant)
      Cek.CekReport res st _logs = Cek.runCekDeBruijn params Cek.tallying Cek.noEmitter term
      status = case res of
        Cek.CekFailure _ -> "FAIL"
        _ -> "OK"
   in status ++ "\n" ++ display st

-- | Readable rendering of a program with generated variable names.
prettyProgram :: Program -> String
prettyProgram (UPLC.Program _ _ body) =
  case runExcept (runQuoteT (UPLC.unDeBruijnTerm (UPLC.termMapNames UPLC.fakeNameDeBruijn body))) of
    Left (err :: UPLC.FreeVariableError) -> "free variable: " ++ show err
    Right named -> render (prettyPlcClassic (UPLC.Program () (UPLC.Version 1 1 0) named))

-- | Parse a program in the classic textual syntax (as written by
-- 'prettyProgram') back into a DeBruijn program.
parseProgramText :: String -> Either String Program
parseProgramText text = do
  UPLC.Program _ ver named <-
    either (\(e :: ParserErrorBundle) -> Left (display e)) Right $
      runExcept (runQuoteT (UPLCParser.parseProgram (T.pack text)))
  db <- either (\(e :: UPLC.FreeVariableError) -> Left (show e)) Right $
    runExcept (UPLC.deBruijnTerm named)
  pure (UPLC.Program () ver (UPLC.termMapNames UPLC.unNameDeBruijn (() <$ db)))
