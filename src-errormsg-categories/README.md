# Six-category error message rig

A second error-collection rig, organised by **failure category** rather
than by individual diagnostic. Each case is a single-file `.patch` that,
applied to a real validator under `src/`, injects a specific bug, and
its sibling `.err` is the captured GHC / Plinth / Plutarch diagnostic.

This rig is independent of `src-errormsg-validators/` — neither rig
overrides or replaces the other, and case names are disjoint.

## Categories

Three Plinth categories and three Plutarch categories, two to four
patches each.

```mermaid
graph TD
  PL[Plinth]
  PL --> PLUSF[PL-USF<br/>Unsupported Haskell features]
  PL --> PLSTG[PL-STG<br/>Stage errors]
  PL --> PLFLG[PL-FLG<br/>GHC/plugin flag misconfiguration]
  PT[Plutarch]
  PT --> PTDRV[PT-DRV<br/>PlutusType derivation errors]
  PT --> PTSYN[PT-SYN<br/>let/plet, -&gt;/:--&gt; mix-ups]
  PT --> PTDAT[PT-DAT<br/>PAsData wrap/unwrap confusion]
```

### Plinth (Plinth-only `.patch` per case)

| Case | Validator | Bug | Expected diagnostic |
|------|-----------|-----|---------------------|
| `PL-USF-01-Voting-GADT` | `Voting/Contracts/VotingPlinth.hs` | Enable `GADTs`, define a witness GADT consumed by `plinthc` | `Unsupported feature: Following extensions are not supported: GADTs` |
| `PL-USF-02-Crowdfund-PolyKinds` | `Crowdfund/Contracts/CrowdfundPlinth.hs` | Enable `PolyKinds`, give `plinthc` code that infers polykinded `Proxy'` | `Unsupported feature: Following extensions are not supported: PolyKinds` |
| `PL-USF-03-Hydra-Existential` | `Hydra/Contracts/HeadPlinth.hs` | Enable `ExistentialQuantification`, pack/open an existential inside `plinthc` | `Reference to a name which is not a local, a builtin, or an external INLINABLE function: Type variable: a` |
| `PL-STG-01-Settings-Closure` | `Settings/Contracts/SettingsPlinth.hs` | `mkScaledFee multiplier = plinthc (\fee -> fee * multiplier)` — captures runtime `multiplier` | `... Variable multiplier` stage error |
| `PL-STG-02-Constitution-RuntimeCapture` | `Constitution/Contracts/ConstitutionSortedPlinth.hs` | `mkThresholdValidator threshold = plinthc (\actual -> ... threshold ...)` | `... Variable threshold` stage error |
| `PL-STG-03-Crowdfund-RuntimeCapture` | `Crowdfund/Contracts/CrowdfundPlinth.hs` | `mkBoundedValidator cap = plinthc (\amount -> ... cap ...)` | `... Variable cap` stage error |
| `PL-FLG-01-Vesting-BogusPluginOption` | `Vesting/Contracts/VestingPlinth.hs` | `-fplugin-opt Plinth.Plugin:bogus-option` | `PlutusTx.Plugin: failed to parse options: Unrecognised option: "bogus-option"` |
| `PL-FLG-02-Voting-BadTargetVersion` | `Voting/Contracts/VotingPlinth.hs` | `-fplugin-opt Plinth.Plugin:target-version=not.a.version` | `Cannot parse value "not.a.version" for option "target-version" into type Int` |

Note on PL-FLG. The modern Plinth plugin actively rewrites the dangerous
GHC defaults (`-fignore-interface-pragmas`, `-fomit-interface-pragmas`,
`-ffull-laziness`, `-fspec-constr`, `-fspecialise`, `-fstrictness`,
`-funbox-strict-fields`, `-funbox-small-strict-fields`) in its
`driverPlugin`, and it auto-adds `INLINEABLE` to any binding that
lacks an inline pragma via `addInlineables`. As a result the historical
"forgot `-fno-ignore-interface-pragmas`" failure modes from the
plutus-tx README no longer fire — the plugin compensates. The only
flag-level mistakes that still surface as compile-time errors live
inside the `Plinth.Plugin:*` option namespace, which is what PL-FLG
demonstrates.

### Plutarch (Plutarch-only `.patch` per case)

| Case | Source file | Bug | Expected diagnostic |
|------|-------------|-----|---------------------|
| `PT-DRV-01-Crowdfund-AsDataRecMultiCtor` | `Crowdfund/Types/CrowdfundState.hs` | `DeriveAsDataRec` on multi-constructor `PCrowdfundRedeemer` | `Deriving record encoding only works with types with single constructor. More than one constructor is found.` |
| `PT-DRV-02-Vesting-StructNonData` | `Vesting/Types/VestingState.hs` | `pvdAmount` changed to `Term s PInteger` (non-`PData` inner repr) | `Data representation can only hold types whose inner most representation is PData ... Inner most representation of "PInteger" is "POpaque"` |
| `PT-DRV-03-Vesting-TagNonEnum` | `Vesting/Types/VestingState.hs` | `DeriveAsTag` on `PVestingRedeemer` whose ctor carries `PAsData PInteger` | `DeriveAsTag only supports constructors without arguments. However, at constructor #1, I got: '[Term s (PAsData PInteger)]` |
| `PT-SYN-01-Vesting-LetVsPlet` | `Vesting/Contracts/Vesting.hs` | `inputs <- pletC ...` replaced with `inputs <- plet ...` inside `unTermCont $ do` | `Couldn't match expected type: TermCont s X with actual type: (Term s X -> Term s b0) -> Term s b0` |
| `PT-SYN-02-Voting-ArrowVsPArrow` | `Voting/Contracts/Voting.hs` | `Term s (PData -> PData -> ...)` instead of `Term s (PData :--> PData :--> ...)` | `Expecting one more argument to 'PData' ... has kind 'S -> *'` |
| `PT-SYN-03-Crowdfund-DollarVsHashApp` | `Crowdfund/Contracts/Crowdfund.hs` | `pfix $ plam ...` instead of `pfix #$ plam ...` in `plistLength` | `Couldn't match expected type: Term s1 ((list0 a1 :--> b) :--> (list0 a1 :--> b))` |
| `PT-DAT-01-Vesting-MissingPFromData` | `Vesting/Contracts/Vesting.hs` | `let beneficiary = pvdBeneficiary` (forgot `pfromData`) | `Couldn't match type 'PAsData PPubKeyHash' with 'PPubKeyHash'` |
| `PT-DAT-02-Crowdfund-MissingPData` | `Crowdfund/Contracts/Crowdfund.hs` | `outWallets #== (pfilterOutKey # currentSigner # wallets)` (forgot `pdata`) | `Couldn't match type: PMap Unsorted PPubKeyHash PInteger with: PAsData (PMap Unsorted PPubKeyHash PInteger)` |
| `PT-DAT-03-Hydra-PIntForPAsData` | `Hydra/Contracts/Head.hs` | `pforgetData ref1` (passed `PTxOutRef` instead of `PAsData PTxOutRef`) | `Couldn't match type 'PAsData a1' with 'PTxOutRef'` |

## Layout

```
src-errormsg-categories/
  PL-USF-01-Voting-GADT/
    Plinth.patch       # unified diff with '# source:' header
    Plinth.hs          # generated: cp <source> + patch
    Plinth.err         # captured GHC / Plinth diagnostic
  ...
  PT-DAT-03-Hydra-PIntForPAsData/
    Plutarch.patch
    Plutarch.hs
    Plutarch.err
  run.sh
  README.md
```

Per case the `.hs` file is a **generated** copy of the upstream
validator (or types module) with the patch applied. The `.err` file
is the filtered GHC diagnostic. The `.patch` file is the source of
truth — the `# source:` header at the top tells `run.sh` which file
under `src/` to copy before applying the diff.

## Workflow

```bash
nix develop                                  # provides GHC + cabal + project deps
src-errormsg-categories/run.sh               # generate + compile + collect, every case
src-errormsg-categories/run.sh PL-STG        # restrict to one prefix
src-errormsg-categories/run.sh PT-DRV-01     # restrict to one case
```

`run.sh` is the only script in this directory. For every
`<case>/<variant>.patch` (variant = `Plinth` or `Plutarch`) it:

1. Reads the `# source:` header from the patch.
2. Copies that upstream file from `src/` to `<case>/<variant>.hs`.
3. Applies the diff with `patch -p1`.
4. Compiles the result with
   `cabal exec ghc -- -Wall -fforce-recomp -ferror-spans -c
   -package plinth-plutarch-paper-code` plus the project's
   default-extensions, capturing stdout+stderr.
5. Strips the cabal/nix preamble and the SGR escapes Plinth emits
   around its caret underlines, then writes the result to
   `<case>/<variant>.err`.

Per-case verdict printed on stdout:

* `errors captured`        — GHC failed (expected for every case here).
* `warnings captured`      — GHC succeeded but emitted warnings.
* `clean (no diagnostics)` — the bug didn't fire (regression).

## Adding a new case

1. Pick a target validator under `src/` whose shape supports the bug
   you want to demonstrate.
2. Hand-edit a copy of that file to inject the bug.
3. Generate the patch with
   `diff -u src/<path> /tmp/<modified> | sed 's|^--- .*|--- a/<Variant>.hs|; s|^+++ .*|+++ b/<Variant>.hs|'`.
4. Prepend a `# source:` line pointing at the upstream file, plus any
   explanatory header comments (every line that should be ignored by
   `patch` must start with `#`).
5. `src-errormsg-categories/run.sh <case-prefix>` to verify the
   diagnostic.
