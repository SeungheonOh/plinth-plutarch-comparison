{- | Shared evaluation harness for the cross-language benchmark.

  cross-bench export [DIR]
      Write DIR/<Validator>/{cases.csv, plinth.flat, plutarch.flat} for every
      validator. Fails if Plinth or Plutarch disagree with a case's expectation.

  cross-bench run [DIR] [--validator V] [--no-fail]
      Evaluate every script found in DIR/<Validator>/ on every case of that
      validator under cost-model variants C and E, print a CSV report on
      stdout and an agreement summary on stderr. Exits non-zero when a script
      disagrees with a case's expected result, unless --no-fail is given.

DIR defaults to /Users/sho/fun/cross-bench-data.
-}
module Main (main) where

import Control.Monad (forM, forM_, unless, when)
import CrossBench.Cases (CaseKind (..), CaseSpec (..), ValidatorSpec (..), caseKindName, validatorSpecs)
import CrossBench.Csv (parseCsv, renderRow)
import CrossBench.Eval
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isPrefixOf, isSuffixOf, nub, sort, (\\))
import Data.Maybe (fromMaybe)
import PlutusCore.Data (Data)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.Environment (getArgs)
import System.Exit (ExitCode (ExitFailure), exitWith)
import System.FilePath ((</>))
import System.IO (BufferMode (LineBuffering), hFlush, hPutStrLn, hSetBuffering, stderr, stdout)
import Text.Read (readMaybe)
import UntypedPlutusCore qualified as UPLC

defaultDataDir :: FilePath
defaultDataDir = "/Users/sho/fun/cross-bench-data"

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  case args of
    "export" : rest -> case rest of
      [] -> exportAll defaultDataDir
      [dir] | not ("-" `isPrefixOf` dir) -> exportAll dir
      _ -> usage
    "run" : rest -> either (const usage) runAll (parseRunOptions rest)
    "inspect" : rest -> either (const usage) inspect (parseRunOptions rest)
    ["assemble", input, output] -> do
      text <- readFile input
      case parseProgramText text of
        Left err -> hPutStrLn stderr err >> exitWith (ExitFailure 1)
        Right prog -> do
          let bytes = encodeFlat prog
          writeFile output (encodeHex bytes ++ "\n")
          hPutStrLn stderr (output ++ ": flat " ++ show (BS.length bytes) ++ " bytes")
    _ -> usage

usage :: IO a
usage = do
  hPutStrLn stderr "usage: cross-bench export [DIR]"
  hPutStrLn stderr "       cross-bench run [DIR] [--validator V] [--no-fail]"
  hPutStrLn stderr "       cross-bench inspect [DIR] --validator V [--case NAME]"
  hPutStrLn stderr "       cross-bench assemble IN.uplc OUT.flat.hex"
  exitWith (ExitFailure 2)

-- ============================================================================
-- Results
-- ============================================================================

{- | Render an evaluation outcome the way it appears in the @expected@ and
@result@ columns: OK / FAIL for validators, the returned Integer for
integer-returning scripts (NONINT if one succeeds with anything else).
-}
renderOutcome :: Bool -> Outcome -> String
renderOutcome _ (Failed _) = "FAIL"
renderOutcome False _ = "OK"
renderOutcome True (SucceededInteger n) = show n
renderOutcome True Succeeded = "NONINT"

renderExpectation :: Bool -> String
renderExpectation True = "OK"
renderExpectation False = "FAIL"

-- ============================================================================
-- export
-- ============================================================================

{- | Export every validator whose Plinth and Plutarch scripts agree with the
expectation of every case. A validator with any disagreement is reported on
stderr and not written (its directory is left untouched), and the command then
exits non-zero.
-}
exportAll :: FilePath -> IO ()
exportAll dir = do
  rejected <- fmap concat . forM validatorSpecs $ \spec -> do
    let (rows, problems, warnings) = checkValidator spec
    forM_ warnings $ \w -> hPutStrLn stderr ("warning: " ++ vsName spec ++ ": " ++ w)
    if null problems
      then do
        writeValidator spec rows
        pure []
      else do
        hPutStrLn stderr $
          "ERROR: "
            ++ vsName spec
            ++ ": not exported, Plinth/Plutarch disagree with the expected result ("
            ++ show (length problems)
            ++ " problems):"
        mapM_ (hPutStrLn stderr . ("  " ++)) problems
        pure [vsName spec]
  hPutStrLn stderr $
    "exported "
      ++ show (length validatorSpecs - length rejected)
      ++ " of "
      ++ show (length validatorSpecs)
      ++ " validators to "
      ++ dir
  unless (null rejected) $ do
    hPutStrLn stderr ("export FAILED for: " ++ unwords rejected)
    exitWith (ExitFailure 1)
  where
    writeValidator spec rows = do
      let vdir = dir </> vsName spec
          plinthFlat = encodeFlat (vsPlinth spec)
          plutarchFlat = encodeFlat (vsPlutarch spec)
          count k = length [() | c <- vsCases spec, csKind c == k]
      createDirectoryIfMissing True vdir
      writeFile (vdir </> "cases.csv") $
        unlines (renderRow ["name", "kind", "expected", "args"] : map renderRow rows)
      BS.writeFile (vdir </> "plinth.flat") plinthFlat
      BS.writeFile (vdir </> "plutarch.flat") plutarchFlat
      hPutStrLn stderr $
        vsName spec
          ++ ": "
          ++ show (count BenchCase)
          ++ " bench, "
          ++ show (count TestCase)
          ++ " test cases; plinth.flat "
          ++ show (BS.length plinthFlat)
          ++ " bytes, plutarch.flat "
          ++ show (BS.length plutarchFlat)
          ++ " bytes"

{- | Evaluate the Plinth and Plutarch scripts of a validator on all its cases
under both cost-model variants. Returns the CSV rows, hard problems
(disagreements) and soft warnings.
-}
checkValidator :: ValidatorSpec -> ([[String]], [String], [String])
checkValidator spec =
  let results = map checkCase (vsCases spec)
      duplicates =
        [ "duplicate " ++ caseKindName k ++ " case name " ++ show n
        | k <- [BenchCase, TestCase]
        , let names = [csName c | c <- vsCases spec, csKind c == k]
        , n <- nub (names \\ nub names)
        ]
   in ( [row | (row, _, _) <- results]
      , duplicates ++ concat [ps | (_, ps, _) <- results]
      , concat [ws | (_, _, ws) <- results]
      )
  where
    intMode = vsReturnsInteger spec
    checkCase c =
      let label = caseKindName (csKind c) ++ " case " ++ show (csName c)
          outcomes compiler prog =
            [ (compiler, v, renderOutcome intMode o, o)
            | v <- allCostVariants
            , let o = erOutcome (evaluate v prog (csArgs c))
            ]
          plinthResults = outcomes "Plinth" (vsPlinth spec)
          plutarchResults = outcomes "Plutarch" (vsPlutarch spec)
          plinthDefault = head [r | (_, v, r, _) <- plinthResults, v == VariantE]
          expected = maybe plinthDefault renderExpectation (csExpectSuccess c)
          mismatches =
            [ label ++ ": " ++ compiler ++ " (variant " ++ costVariantName v ++ ") gives " ++ r ++ ", expected " ++ expected ++ failureDetail o
            | (compiler, v, r, o) <- plinthResults ++ plutarchResults
            , r /= expected
            ]
          failureDetail (Failed err) = "\n      " ++ take 600 (unwords (words err))
          failureDetail _ = ""
          referenceProblems = case csReference c of
            Just ref
              | show ref /= expected ->
                  [label ++ ": Haskell reference gives " ++ show ref ++ ", script gives " ++ expected]
            _ -> []
          integerProblems =
            [label ++ ": expected an Integer result, got " ++ expected | intMode, (readMaybe expected :: Maybe Integer) == Nothing]
          nameWarnings =
            [ label ++ ": name says reject but Plinth accepts"
            | csKind c == BenchCase, not intMode, "(reject)" `isSuffixOf` csName c, expected == "OK"
            ]
              ++ [ label ++ ": name does not say reject but Plinth rejects"
                 | csKind c == BenchCase, not intMode, not ("(reject)" `isSuffixOf` csName c), expected == "FAIL"
                 ]
          row =
            [ csName c
            , caseKindName (csKind c)
            , expected
            , joinWith ';' (map (encodeHex . serialiseData) (csArgs c))
            ]
       in (row, mismatches ++ referenceProblems ++ integerProblems, nameWarnings)

joinWith :: Char -> [String] -> String
joinWith _ [] = ""
joinWith sep (x : xs) = x ++ concatMap (sep :) xs

splitOn :: Char -> String -> [String]
splitOn sep s = case break (== sep) s of
  (a, []) -> [a]
  (a, _ : rest) -> a : splitOn sep rest

-- ============================================================================
-- run
-- ============================================================================

data RunOptions = RunOptions
  { roDir :: FilePath
  , roValidator :: Maybe String
  , roNoFail :: Bool
  , roCase :: Maybe String
  }

parseRunOptions :: [String] -> Either String RunOptions
parseRunOptions = go (RunOptions defaultDataDir Nothing False Nothing) False
  where
    go opts _ [] = Right opts
    go opts seenDir ("--case" : c : rest) = go opts {roCase = Just c} seenDir rest
    go opts seenDir ("--validator" : v : rest) = go opts {roValidator = Just v} seenDir rest
    go opts seenDir ("--no-fail" : rest) = go opts {roNoFail = True} seenDir rest
    go opts False (d : rest) | not ("-" `isPrefixOf` d) = go opts {roDir = d} True rest
    go _ _ (a : _) = Left ("unexpected argument " ++ a)

data RunCase = RunCase
  { rcName :: String
  , rcKind :: String
  , rcExpected :: String
  , rcArgs :: [Data]
  }

data LoadedScript = LoadedScript
  { lsCompiler :: String
  , lsProgram :: Program
  , lsFlatBytes :: Int
  , lsCborBytes :: Int
  }

knownScriptFiles :: [FilePath]
knownScriptFiles = ["plinth.flat", "plutarch.flat", "moist.flat.hex", "moist-size.flat.hex", "aiken.cbor.hex"]

scriptSuffixes :: [String]
scriptSuffixes = [".flat.hex", ".cbor.hex", ".flat"]

scriptStem :: FilePath -> Maybe String
scriptStem f =
  case [take (length f - length suf) f | suf <- scriptSuffixes, suf `isSuffixOf` f, length f > length suf] of
    stem : _ -> Just stem
    [] -> Nothing

runAll :: RunOptions -> IO ()
runAll opts = do
  validators <- case roValidator opts of
    Just v -> pure [v]
    Nothing -> discoverValidators (roDir opts)
  failures <- newIORef (0 :: Int)
  putStrLn (renderRow ["variant", "validator", "case", "kind", "expected", "compiler", "result", "cpu", "mem", "flat_bytes", "cbor_bytes"])
  forM_ validators $ \v -> do
    n <- runValidator (roDir opts) v
    modifyIORef' failures (+ n)
  hFlush stdout
  total <- readIORef failures
  when (total > 0) $
    if roNoFail opts
      then hPutStrLn stderr (problemSummary total ++ " (ignored: --no-fail)")
      else do
        hPutStrLn stderr (problemSummary total)
        exitWith (ExitFailure 1)

problemSummary :: Int -> String
problemSummary n = show n ++ " problem(s): results differing from expected, or unreadable cases/scripts"

-- | Validator directories under DIR that hold a cases.csv, in contract order first.
discoverValidators :: FilePath -> IO [String]
discoverValidators dir = do
  entries <- sort <$> listDirectory dir
  withCases <- fmap concat . forM entries $ \e -> do
    isDir <- doesDirectoryExist (dir </> e)
    hasCases <- if isDir then doesFileExist (dir </> e </> "cases.csv") else pure False
    pure [e | hasCases]
  let known = map vsName validatorSpecs
  pure (filter (`elem` withCases) known ++ filter (`notElem` known) withCases)

-- | Run one validator; returns the number of disagreements (including unloadable scripts and cases).
runValidator :: FilePath -> String -> IO Int
runValidator dir validator = do
  let vdir = dir </> validator
  casesExist <- doesFileExist (vdir </> "cases.csv")
  if not casesExist
    then do
      hPutStrLn stderr (validator ++ ": ERROR: " ++ (vdir </> "cases.csv") ++ " not found")
      pure 1
    else do
      casesOrErr <- readCases (vdir </> "cases.csv")
      case casesOrErr of
        Left err -> do
          hPutStrLn stderr (validator ++ ": ERROR: cases.csv: " ++ err)
          pure 1
        Right cases -> do
          (scripts, loadErrors) <- loadScripts validator vdir
          mismatches <- forM allCostVariants $ \variant ->
            fmap concat . forM cases $ \c ->
              fmap concat . forM scripts $ \s -> do
                let res = evaluate variant (lsProgram s) (rcArgs c)
                    intMode = isIntegerExpectation (rcExpected c)
                    result = renderOutcome intMode (erOutcome res)
                putStrLn $
                  renderRow
                    [ costVariantName variant
                    , validator
                    , rcName c
                    , rcKind c
                    , rcExpected c
                    , lsCompiler s
                    , result
                    , show (erCpu res)
                    , show (erMem res)
                    , show (lsFlatBytes s)
                    , show (lsCborBytes s)
                    ]
                pure [(lsCompiler s, variant, c, result) | result /= rcExpected c]
          summarise validator cases scripts (concat mismatches)
          pure (length (concat mismatches) + loadErrors)

isIntegerExpectation :: String -> Bool
isIntegerExpectation s = (readMaybe s :: Maybe Integer) /= Nothing

readCases :: FilePath -> IO (Either String [RunCase])
readCases path = do
  text <- readFile path
  pure $ do
    rows <- parseCsv text
    case rows of
      ["name", "kind", "expected", "args"] : body -> mapM toCase (zip [2 :: Int ..] body)
      _ -> Left "missing or unexpected header (want name,kind,expected,args)"
  where
    toCase (ln, [name, kind, expected, argsField]) = do
      args <-
        mapM
          (\h -> either (\e -> Left ("line " ++ show ln ++ ": " ++ e)) Right (decodeHex h >>= deserialiseData))
          (if null argsField then [] else splitOn ';' argsField)
      pure (RunCase name kind expected args)
    toCase (ln, fields) = Left ("line " ++ show ln ++ ": expected 4 fields, got " ++ show (length fields))

{- | Load every script in a validator directory: the known compilers first,
then any other @*.flat@, @*.flat.hex@ or @*.cbor.hex@ file, named after its
stem. Returns the scripts and the number of files that failed to load.
-}
loadScripts :: String -> FilePath -> IO ([LoadedScript], Int)
loadScripts validator vdir = do
  files <- sort <$> listDirectory vdir
  forM_ (filter (`notElem` files) knownScriptFiles) $ \f ->
    hPutStrLn stderr (validator ++ ": note: " ++ f ++ " not present, skipped")
  let extra = [f | f <- files, f `notElem` knownScriptFiles, scriptStem f /= Nothing]
      ordered = filter (`elem` files) knownScriptFiles ++ extra
      stems = map (fromMaybe "" . scriptStem) ordered
      names = [if length (filter (== s) stems) > 1 then f else s | (f, s) <- zip ordered stems]
  loaded <- forM (zip ordered names) $ \(f, name) -> do
    raw <- BS.readFile (vdir </> f)
    let bytes
          | ".hex" `isSuffixOf` f = decodeHex (BS8.unpack raw)
          | otherwise = Right raw
        result = do
          b <- bytes
          flatBytes <- unwrapCbor b
          prog <- decodeFlat flatBytes
          pure
            LoadedScript
              { lsCompiler = name
              , lsProgram = prog
              , lsFlatBytes = BS.length flatBytes
              , lsCborBytes = fromIntegral (LBS.length (cborWrap flatBytes))
              }
    case result of
      Left err -> do
        hPutStrLn stderr (validator ++ ": ERROR: cannot load " ++ f ++ ": " ++ err)
        pure (Left ())
      Right s -> do
        let UPLC.Program _ ver _ = lsProgram s
        when (ver /= UPLC.Version 1 1 0) $
          hPutStrLn stderr (validator ++ ": note: " ++ f ++ " has program version " ++ show ver)
        pure (Right s)
  pure ([s | Right s <- loaded], length [() | Left () <- loaded])

summarise :: String -> [RunCase] -> [LoadedScript] -> [(String, CostVariant, RunCase, String)] -> IO ()
summarise validator cases scripts mismatches = do
  let nBench = length [() | c <- cases, rcKind c == "bench"]
      nTest = length [() | c <- cases, rcKind c == "test"]
      perScript = length cases * length allCostVariants
  hPutStrLn stderr $
    validator ++ ": " ++ show nBench ++ " bench + " ++ show nTest ++ " test cases x " ++ show (length allCostVariants) ++ " variants"
  forM_ scripts $ \s -> do
    let bad = [m | m@(compiler, _, _, _) <- mismatches, compiler == lsCompiler s]
        status = if null bad then "agrees" else "DISAGREES"
    hPutStrLn stderr $
      "  "
        ++ padRight 12 (lsCompiler s)
        ++ " "
        ++ status
        ++ " "
        ++ show (perScript - length bad)
        ++ "/"
        ++ show perScript
        ++ "  (flat "
        ++ show (lsFlatBytes s)
        ++ " B, cbor "
        ++ show (lsCborBytes s)
        ++ " B)"
    let grouped = [((rcKind c, rcName c), (v, r, rcExpected c)) | (_, v, c, r) <- bad]
        keys = nub (map fst grouped)
    forM_ (take 15 keys) $ \k@(kind, name) -> do
      let entries = [e | (k', e) <- grouped, k' == k]
          variants = concatMap (\(v, _, _) -> costVariantName v) entries
          (_, got, want) = head entries
      hPutStrLn stderr ("      " ++ kind ++ " " ++ show name ++ " [" ++ variants ++ "]: expected " ++ want ++ ", got " ++ got)
    when (length keys > 15) $
      hPutStrLn stderr ("      ... and " ++ show (length keys - 15) ++ " more")

padRight :: Int -> String -> String
padRight n s = s ++ replicate (n - length s) ' '

-- ============================================================================
-- inspect
-- ============================================================================

{- | Without --case, write a readable rendering of every script of the validator
to DIR/<Validator>/pretty/<compiler>.uplc. With --case NAME, print the
variant C cost breakdown (machine steps and builtins) of every script on that
case.
-}
inspect :: RunOptions -> IO ()
inspect opts = case roValidator opts of
  Nothing -> usage
  Just validator -> do
    let vdir = roDir opts </> validator
    (scripts, _) <- loadScripts validator vdir
    case roCase opts of
      Nothing -> do
        createDirectoryIfMissing True (vdir </> "pretty")
        forM_ scripts $ \s -> do
          let out = vdir </> "pretty" </> (lsCompiler s ++ ".uplc")
          writeFile out (prettyProgram (lsProgram s) ++ "\n")
          hPutStrLn stderr ("wrote " ++ out)
      Just name -> do
        casesOrErr <- readCases (vdir </> "cases.csv")
        case casesOrErr of
          Left err -> hPutStrLn stderr err >> exitWith (ExitFailure 1)
          Right cases -> case [c | c <- cases, rcName c == name] of
            [] -> hPutStrLn stderr ("no case named " ++ show name) >> exitWith (ExitFailure 1)
            c : _ -> forM_ scripts $ \s -> do
              putStrLn ("=== " ++ lsCompiler s)
              putStrLn (tallyReport VariantC (lsProgram s) (rcArgs c))
