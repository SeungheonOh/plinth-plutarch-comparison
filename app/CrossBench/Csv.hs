-- | Minimal RFC 4180 CSV rendering and parsing for the cross-bench data files.
module CrossBench.Csv (
  renderRow,
  parseCsv,
) where

-- | Render one CSV row. Fields containing a comma, quote or line break are quoted.
renderRow :: [String] -> String
renderRow = go
  where
    go [] = ""
    go [f] = field f
    go (f : fs) = field f ++ "," ++ go fs
    field f
      | any (`elem` (",\"\r\n" :: String)) f = "\"" ++ concatMap escape f ++ "\""
      | otherwise = f
    escape '"' = "\"\""
    escape c = [c]

{- | Parse CSV text into rows of fields. Accepts LF or CRLF line endings, quoted
fields with doubled quotes, and ignores blank lines.
-}
parseCsv :: String -> Either String [[String]]
parseCsv = fmap (filter (/= [""])) . rows (1 :: Int)
  where
    rows _ [] = Right []
    rows ln s = do
      (r, rest) <- row ln s []
      (r :) <$> rows (ln + 1) rest

    row ln s acc = do
      (f, rest) <- fieldP ln s
      case rest of
        ',' : rest' -> row ln rest' (f : acc)
        '\r' : '\n' : rest' -> Right (reverse (f : acc), rest')
        '\n' : rest' -> Right (reverse (f : acc), rest')
        [] -> Right (reverse (f : acc), [])
        c : _ -> Left ("line " ++ show ln ++ ": unexpected character " ++ show c)

    fieldP ln ('"' : s) = quoted ln s ""
    fieldP _ s = Right (break (`elem` (",\r\n" :: String)) s)

    quoted ln ('"' : '"' : s) acc = quoted ln s ('"' : acc)
    quoted _ ('"' : s) acc = Right (reverse acc, s)
    quoted ln (c : s) acc = quoted ln s (c : acc)
    quoted ln [] _ = Left ("line " ++ show ln ++ ": unterminated quoted field")
