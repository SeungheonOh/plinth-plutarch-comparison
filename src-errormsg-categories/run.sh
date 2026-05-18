#!/usr/bin/env bash
# Single workflow script for src-errormsg-categories:
#
#   1. Generate <case>/<variant>.hs by `cp`-ing the upstream source file
#      (validator OR types module) from src/ and applying
#      <case>/<variant>.patch on top of it.
#   2. Compile the generated <variant>.hs with `cabal exec ghc -- -Wall
#      -fforce-recomp -c …` and capture the diagnostic output.
#   3. Filter the cabal/nix preamble out of the captured output and write
#      the result to <case>/<variant>.err next to the source file.
#
# This rig groups cases by category prefix:
#
#   PL-USF-*   Plinth: unsupported Haskell feature
#   PL-STG-*   Plinth: stage error
#   PL-FLG-*   Plinth: missing GHC flag / unwanted optimization
#   PT-DRV-*   Plutarch: PlutusType derivation error
#   PT-SYN-*   Plutarch: let/plet, ->/:--> mix-up
#   PT-DAT-*   Plutarch: PAsData wrap/unwrap confusion
#
# Each case directory holds at most one `Plinth.patch` (Plinth-side bug)
# and one `Plutarch.patch` (Plutarch-side bug). Plinth-only cases skip
# the Plutarch step and vice versa.
#
# Usage:
#   src-errormsg-categories/run.sh                # process every case
#   src-errormsg-categories/run.sh PL-FLG         # only PL-FLG-* cases
#   src-errormsg-categories/run.sh PT-DRV-01      # exact-prefix match
#
# Requires the project's Nix dev shell (`nix develop`). The compiler is
# whichever GHC cabal resolves; the project pins GHC 9.6.6 with
# plutus-tx-plugin 1.64.0.0 and plutarch 1.10.x. GHC is expected to
# fail on every case — this script always exits 0 unless an unexpected
# `patch`/shell error happens.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERROR_ROOT="$REPO_ROOT/src-errormsg-categories"

declare -a SELECT=()
for arg in "$@"; do
  SELECT+=("$arg")
done

select_matches() {
  local name="$1"
  if [ "${#SELECT[@]}" -eq 0 ]; then
    return 0
  fi
  for needle in "${SELECT[@]}"; do
    if [[ "$name" == *"$needle"* ]]; then
      return 0
    fi
  done
  return 1
}

# 1. Generate: cp upstream source + patch -p1.
apply_patch() {
  local patch_file="$1"
  local out_hs="${patch_file%.patch}.hs"

  local src
  src=$(awk '/^# source:/ { sub(/^# source:[[:space:]]*/, ""); print; exit }' "$patch_file")
  if [ -z "$src" ]; then
    echo "  ! no '# source:' header in $patch_file" >&2
    return 1
  fi

  local src_full="$REPO_ROOT/$src"
  if [ ! -f "$src_full" ]; then
    echo "  ! source $src_full not found" >&2
    return 1
  fi

  cp "$src_full" "$out_hs"
  patch --quiet -p1 -d "$(dirname "$out_hs")" -i "$patch_file"
}

# 2 + 3. Compile and capture the filtered diagnostic.
compile_and_capture() {
  local file="$1"
  local err_out="$2"
  local case_dir
  case_dir="$(dirname "$file")"
  local raw="$case_dir/.${file##*/}.raw"

  (
    cd "$REPO_ROOT" || exit 1
    # `cabal exec` puts the project's package DB on GHC's search path so
    # imports (e.g. `Vesting.Types.VestingState`, `Plutarch.LedgerApi.V3`)
    # resolve to the built library. The default-extensions list mirrors
    # the project's `project-config` cabal stanza, so a standalone
    # compile produces the same language semantics as a normal cabal
    # build.
    cabal exec ghc -- \
      -Wall \
      -fforce-recomp \
      -ferror-spans \
      -c \
      -package plinth-plutarch-paper-code \
      -odir "$case_dir/.build" \
      -hidir "$case_dir/.build" \
      -XBangPatterns -XDataKinds -XDeriveAnyClass -XDeriveGeneric \
      -XDerivingStrategies -XDerivingVia -XFlexibleInstances \
      -XGeneralizedNewtypeDeriving -XImportQualifiedPost -XInstanceSigs \
      -XLambdaCase -XMultiWayIf -XNumericUnderscores -XOverloadedRecordDot \
      -XOverloadedStrings -XQualifiedDo -XRankNTypes -XScopedTypeVariables \
      -XStandaloneDeriving -XTypeApplications -XTypeFamilies \
      -XTypeFamilyDependencies -XTypeOperators -XUndecidableInstances \
      -XViewPatterns \
      "$file"
  ) >"$raw" 2>&1
  local rc=$?

  # Strip cabal/nix bookkeeping plus the SGR escapes Plinth emits around
  # caret underlines (even when `-fdiagnostics-color=never` is on).
  sed -E \
    -e '/^Using saved setting/d' \
    -e '/^Configuration is affected by/d' \
    -e "/^'\\/Users.*cabal.project'/d" \
    -e '/^Loaded package environment from/d' \
    -e '/^warning: Git tree/d' \
    -e $'s/\x1b\\[[0-9;]*[A-Za-z]//g' \
    "$raw" > "$err_out"
  rm -f "$raw"

  return $rc
}

verdict() {
  local rc="$1"
  local err="$2"
  if [ "$rc" -ne 0 ]; then
    echo "errors captured"
  elif grep -q 'warning:\|Compilation Error:' "$err"; then
    echo "warnings captured"
  elif [ -s "$err" ]; then
    echo "diagnostics captured"
  else
    echo "clean (no diagnostics)"
  fi
}

process_case() {
  local case_dir="$1"
  local name
  name="$(basename "$case_dir")"
  select_matches "$name" || return 0

  for variant in Plinth Plutarch; do
    local patch_file="$case_dir/$variant.patch"
    [ -f "$patch_file" ] || continue

    local hs="$case_dir/$variant.hs"
    local err="$case_dir/$variant.err"

    printf '%-50s %s.hs ' "$name" "$variant"

    if ! apply_patch "$patch_file"; then
      printf '... patch failed\n'
      continue
    fi
    printf '... '

    local rc=0
    compile_and_capture "$hs" "$err" || rc=$?
    printf '%s\n' "$(verdict "$rc" "$err")"
  done
}

main() {
  shopt -s nullglob
  for case_dir in "$ERROR_ROOT"/PL-* "$ERROR_ROOT"/PT-*; do
    [ -d "$case_dir" ] || continue
    process_case "$case_dir"
  done
}

main
