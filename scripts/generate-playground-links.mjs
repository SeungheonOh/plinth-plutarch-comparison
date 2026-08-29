#!/usr/bin/env node

import { gzipSync } from "node:zlib";
import { mkdir, readFile, writeFile } from "node:fs/promises";

const playgroundOrigin = "https://plinth.isotopy.xyz/";

const examples = [
  {
    slug: "net-withdraw",
    category: "learn",
    title: "Recursive withdrawals",
    description:
      "The paper's compact introductory example: algebraic data, pattern matching, recursion, and integer arithmetic side by side.",
    plutarch: {
      module: "Sample.Sample",
      entry: "netWithdraw",
      files: ["src/Sample/Sample.hs"],
    },
    plinth: {
      module: "Sample.SamplePlinth",
      entry: "netWithdrawUPLC",
      files: ["src/Sample/SamplePlinth.hs"],
    },
  },
  {
    slug: "smart-tokens",
    title: "Smart Tokens",
    description: "CIP-143 programmable token logic",
    plutarch: {
      module: "SmartTokens.Contracts.ProgrammableLogicBase",
      entry: "mkProgrammableLogicGlobal",
      files: [
        "src/SmartTokens/Contracts/ProgrammableLogicBase.hs",
        "src/SmartTokens/Types/PTokenDirectory.hs",
        "src/SmartTokens/Types/ProgrammableLogicGlobal.hs",
        "src/SmartTokens/Types/ProtocolParams.hs",
      ],
    },
    plinth: {
      module: "SmartTokens.Contracts.ProgrammableLogicBasePlinth",
      entry: "plinthProgrammableLogicGlobalScript",
      files: [
        "src/SmartTokens/Contracts/ProgrammableLogicBasePlinth.hs",
        "src/SmartTokens/Types/PTokenDirectory.hs",
        "src/SmartTokens/Types/ProgrammableLogicGlobal.hs",
        "src/SmartTokens/Types/ProtocolParams.hs",
      ],
    },
  },
  {
    slug: "constitution",
    title: "Guardrail / Constitution",
    description: "Governance proposal guardrails",
    plutarch: {
      module: "Constitution.Contracts.ConstitutionSorted",
      entry: "mkConstitutionValidator",
      files: [
        "src/Constitution/Contracts/ConstitutionSorted.hs",
        "src/Constitution/Types/ConstitutionConfig.hs",
      ],
    },
    plinth: {
      module: "Constitution.Contracts.ConstitutionSortedPlinth",
      entry: "plinthConstitutionScript",
      files: [
        "src/Constitution/Contracts/ConstitutionSortedPlinth.hs",
        "src/Constitution/Types/ConstitutionConfig.hs",
      ],
    },
  },
  {
    slug: "crowdfund",
    title: "Crowdfund",
    description: "Fundraising, withdrawal, and refund validator",
    plutarch: {
      module: "Crowdfund.Contracts.Crowdfund",
      entry: "mkCrowdfundValidator",
      files: [
        "src/Crowdfund/Contracts/Crowdfund.hs",
        "src/Crowdfund/Types/CrowdfundState.hs",
      ],
    },
    plinth: {
      module: "Crowdfund.Contracts.CrowdfundPlinth",
      entry: "plinthCrowdfundScript",
      files: [
        "src/Crowdfund/Contracts/CrowdfundPlinth.hs",
        "src/Crowdfund/Types/CrowdfundState.hs",
      ],
    },
  },
  {
    slug: "hydra-head",
    title: "Hydra Head",
    description: "Hydra head state-machine validator",
    plutarch: {
      module: "Hydra.Contracts.Head",
      entry: "mkHeadValidator",
      files: [
        "src/Hydra/Contracts/Head.hs",
        "src/Hydra/Types/HeadState.hs",
      ],
    },
    plinth: {
      module: "Hydra.Contracts.HeadPlinth",
      entry: "plinthHeadScript",
      files: [
        "src/Hydra/Contracts/HeadPlinth.hs",
        "src/Hydra/Types/HeadState.hs",
      ],
    },
  },
  {
    slug: "settings",
    title: "SundaeSwap NFT / Settings",
    description: "Settings authorization NFT and multisig validator",
    plutarch: {
      module: "Settings.Contracts.Settings",
      entry: "mkSettingsValidator",
      files: [
        "src/Settings/Contracts/Settings.hs",
        "src/Settings/Types/SettingsState.hs",
      ],
    },
    plinth: {
      module: "Settings.Contracts.SettingsPlinth",
      entry: "plinthSettingsScript",
      files: [
        "src/Settings/Contracts/SettingsPlinth.hs",
        "src/Settings/Types/SettingsState.hs",
      ],
    },
  },
  {
    slug: "vesting",
    title: "Vesting",
    description: "Time-locked release of funds",
    plutarch: {
      module: "Vesting.Contracts.Vesting",
      entry: "mkVestingValidator",
      files: [
        "src/Vesting/Contracts/Vesting.hs",
        "src/Vesting/Types/VestingState.hs",
      ],
    },
    plinth: {
      module: "Vesting.Contracts.VestingPlinth",
      entry: "plinthVestingScript",
      files: [
        "src/Vesting/Contracts/VestingPlinth.hs",
        "src/Vesting/Types/VestingState.hs",
      ],
    },
  },
  {
    slug: "certifying",
    title: "Certifying",
    description: "Vote-delegation certificate validation",
    plutarch: {
      module: "Certifying.Contracts.Certifying",
      entry: "mkCertifyingValidator",
      files: ["src/Certifying/Contracts/Certifying.hs"],
    },
    plinth: {
      module: "Certifying.Contracts.CertifyingPlinth",
      entry: "plinthCertifyingScript",
      files: ["src/Certifying/Contracts/CertifyingPlinth.hs"],
    },
  },
  {
    slug: "voting",
    title: "Voting",
    description: "Hot committee credential script",
    plutarch: {
      module: "Voting.Contracts.Voting",
      entry: "mkVotingValidator",
      files: ["src/Voting/Contracts/Voting.hs"],
    },
    plinth: {
      module: "Voting.Contracts.VotingPlinth",
      entry: "plinthVotingScript",
      files: ["src/Voting/Contracts/VotingPlinth.hs"],
    },
  },
  {
    slug: "missing-equality-constraint",
    category: "diagnostics",
    mode: "diagnostic",
    title: "Missing equality constraint",
    description:
      "Compare a missing Eq constraint in Plinth with the corresponding PEq constraint in Plutarch.",
    plutarch: {
      module: "E08Plutarch",
      files: [
        {
          path: "src-errormsg/E08-MissingEq/Plutarch.hs",
          name: "E08Plutarch.hs",
        },
      ],
    },
    plinth: {
      module: "E08Plinth",
      files: [
        {
          path: "src-errormsg/E08-MissingEq/Plinth.hs",
          name: "E08Plinth.hs",
        },
      ],
    },
  },
  {
    slug: "missing-data-constraint",
    category: "diagnostics",
    mode: "diagnostic",
    title: "Missing on-chain data constraint",
    description:
      "See how generic on-chain data requires ToData/UnsafeFromData in Plinth and PIsData in Plutarch.",
    plutarch: {
      module: "E10Plutarch",
      files: [
        {
          path: "src-errormsg/E10-MissingDataConstraint/Plutarch.hs",
          name: "E10Plutarch.hs",
        },
      ],
    },
    plinth: {
      module: "E10Plinth",
      files: [
        {
          path: "src-errormsg/E10-MissingDataConstraint/Plinth.hs",
          name: "E10Plinth.hs",
        },
      ],
    },
  },
  {
    slug: "missing-application-parentheses",
    category: "diagnostics",
    mode: "diagnostic",
    title: "Function application and parentheses",
    description:
      "Contrast ordinary Haskell application with Plutarch's # operator when parentheses are missing.",
    plutarch: {
      module: "E12Plutarch",
      files: [
        {
          path: "src-errormsg/E12-MissingAppParens/Plutarch.hs",
          name: "E12Plutarch.hs",
        },
      ],
    },
    plinth: {
      module: "E12Plinth",
      files: [
        {
          path: "src-errormsg/E12-MissingAppParens/Plinth.hs",
          name: "E12Plinth.hs",
        },
      ],
    },
  },
  {
    slug: "broken-recursion",
    category: "diagnostics",
    mode: "diagnostic",
    title: "Broken recursion",
    description:
      "Compare accidental name shadowing in direct Plinth recursion with an incorrectly constructed Plutarch recursive term.",
    plutarch: {
      module: "E24Plutarch",
      files: [
        {
          path: "src-errormsg/E24-BrokenRecursion/Plutarch.hs",
          name: "E24Plutarch.hs",
        },
      ],
    },
    plinth: {
      module: "E24Plinth",
      files: [
        {
          path: "src-errormsg/E24-BrokenRecursion/Plinth.hs",
          name: "E24Plinth.hs",
        },
      ],
    },
  },
];

const sections = [
  {
    id: "learn",
    title: "Start with the paper example",
    description:
      "A small, complete program that makes the surface-language differences easy to see before moving into ledger APIs.",
  },
  {
    id: "validators",
    title: "Validator case studies",
    description:
      "Production-shaped contracts covering the major Cardano script purposes and common ledger operations.",
  },
  {
    id: "diagnostics",
    title: "Learn from compiler diagnostics",
    description:
      "These projects are intentionally broken. Compile both versions and compare how each language explains the same class of mistake.",
  },
];

function moduleFilename(sourcePath) {
  return sourcePath.replace(/^src\//, "");
}

function browserCompatibleSource(source) {
  // A shared playground project is compiled without the repository's Cabal
  // stanza, so preserve the exact language-extension environment here.
  const extensions = [
    "BangPatterns",
    "DataKinds",
    "DeriveAnyClass",
    "DeriveGeneric",
    "DerivingStrategies",
    "DerivingVia",
    "FlexibleInstances",
    "GeneralizedNewtypeDeriving",
    "ImportQualifiedPost",
    "InstanceSigs",
    "LambdaCase",
    "MultiWayIf",
    "NumericUnderscores",
    "OverloadedRecordDot",
    "OverloadedStrings",
    "QualifiedDo",
    "RankNTypes",
    "ScopedTypeVariables",
    "StandaloneDeriving",
    "TypeApplications",
    "TypeFamilies",
    "TypeFamilyDependencies",
    "TypeOperators",
    "UndecidableInstances",
    "ViewPatterns",
  ];
  const pragmas = extensions.map((extension) => `{-# LANGUAGE ${extension} #-}`).join("\n");
  return `${pragmas}\n${source}`;
}

function plutarchMain(example, implementation) {
  return `module Main where

import Plutarch.Browser (exportScript)
import Plutarch.Internal.Term (compile)
import ${implementation.module} (${implementation.entry})

main :: IO ()
main = exportScript "${example.slug}-plutarch" $ compile mempty ${implementation.entry}
`;
}

function plinthMain(implementation) {
  return `module Main where

import ${implementation.module} (${implementation.entry})

main :: IO ()
main = ${implementation.entry} \`seq\` pure ()
`;
}

function diagnosticMain(implementation) {
  return `module Main where

import ${implementation.module} ()

main :: IO ()
main = pure ()
`;
}

async function projectFor(example, language) {
  const implementation = example[language];
  const modules = [
    {
      name: "Main.hs",
      source:
        example.mode === "diagnostic"
          ? diagnosticMain(implementation)
          : language === "plutarch"
          ? plutarchMain(example, implementation)
          : plinthMain(implementation),
    },
  ];

  for (const file of implementation.files) {
    const sourcePath = typeof file === "string" ? file : file.path;
    modules.push({
      name: typeof file === "string" ? moduleFilename(sourcePath) : file.name,
      source: browserCompatibleSource(await readFile(sourcePath, "utf8")),
    });
  }

  return {
    v: 1,
    modules,
    active: "Main.hs",
    arguments: [],
  };
}

function projectUrl(project) {
  const compressed = gzipSync(Buffer.from(JSON.stringify(project)), { mtime: 0 });
  const payload = `z${compressed.toString("base64url")}`;
  return `${playgroundOrigin}#p=${payload}`;
}

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

const linkedExamples = [];
for (const example of examples) {
  linkedExamples.push({
    ...example,
    category: example.category ?? "validators",
    plinthUrl: projectUrl(await projectFor(example, "plinth")),
    plutarchUrl: projectUrl(await projectFor(example, "plutarch")),
  });
}

const markdown = [
  "# Funarch playground examples",
  "",
  "Each link opens a complete project in [Plinth Playground](https://plinth.isotopy.xyz/) with its source loaded and ready to compile.",
  "",
  "The final section contains intentional mistakes from the paper's compiler-diagnostics study; those examples are expected to fail and are useful for comparing the two error messages.",
  "",
  ...sections.flatMap((section) => [
    `## ${section.title}`,
    "",
    section.description,
    "",
    ...linkedExamples
      .filter((example) => example.category === section.id)
      .flatMap((example) => [
        `### ${example.title}`,
        "",
        example.description,
        "",
        `- [Open the Plinth ${example.mode === "diagnostic" ? "error example" : "implementation"}](${example.plinthUrl})`,
        `- [Open the Plutarch ${example.mode === "diagnostic" ? "error example" : "implementation"}](${example.plutarchUrl})`,
        "",
      ]),
  ]),
].join("\n");

const collections = sections
  .map((section) => {
    const cards = linkedExamples
      .filter((example) => example.category === section.id)
      .map(
        (example) => `
        <article class="example">
          <div class="example-heading">
            <h3>${escapeHtml(example.title)}</h3>
            <span class="label${example.mode === "diagnostic" ? " diagnostic" : ""}">${
              example.mode === "diagnostic"
                ? "Intentional error"
                : section.id === "learn"
                  ? "Guided example"
                  : "Case study"
            }</span>
          </div>
          <p>${escapeHtml(example.description)}</p>
          <ul>
            <li><a href="${escapeHtml(example.plinthUrl)}">Plinth <span aria-hidden="true">→</span></a></li>
            <li><a href="${escapeHtml(example.plutarchUrl)}">Plutarch <span aria-hidden="true">→</span></a></li>
          </ul>
        </article>`,
      )
      .join("");

    return `
      <section class="collection" aria-labelledby="${section.id}-heading">
        <div class="collection-heading">
          <h2 id="${section.id}-heading">${escapeHtml(section.title)}</h2>
          <p>${escapeHtml(section.description)}</p>
        </div>
        <div class="examples">${cards}
        </div>
      </section>`;
  })
  .join("");

const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Plinth and Plutarch smart-contract examples ready to compile in the browser.">
  <title>Funarch playground examples</title>
  <style>
    :root { color-scheme: light; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; color: #17211d; background: #f7f9f8; }
    * { box-sizing: border-box; }
    body { margin: 0; }
    main { width: min(820px, calc(100% - 32px)); margin: 0 auto; padding: 56px 0 80px; }
    header { padding-bottom: 30px; border-bottom: 1px solid #ced8d3; }
    h1 { margin: 0 0 12px; font: 700 clamp(2rem, 7vw, 3.5rem)/1.04 ui-sans-serif, system-ui, sans-serif; letter-spacing: -0.055em; }
    header p { max-width: 650px; margin: 0; color: #55635d; line-height: 1.65; }
    .collection { padding: 34px 0 8px; border-bottom: 1px solid #ced8d3; }
    .collection-heading { max-width: 660px; margin-bottom: 24px; }
    h2 { margin: 0 0 7px; font: 700 1.3rem/1.35 ui-sans-serif, system-ui, sans-serif; letter-spacing: -0.025em; }
    .collection-heading p, .example p { margin: 0; color: #66736d; font-size: .86rem; line-height: 1.6; }
    .examples { border-top: 1px solid #dbe2df; }
    .example { padding: 22px 0 24px; border-bottom: 1px solid #dbe2df; }
    .example:last-child { border-bottom: 0; }
    .example-heading { display: flex; align-items: baseline; justify-content: space-between; gap: 16px; margin-bottom: 7px; }
    h3 { margin: 0; font: 650 1rem/1.4 ui-sans-serif, system-ui, sans-serif; letter-spacing: -0.012em; }
    .label { flex: none; padding: 3px 7px; border: 1px solid #bfd1ca; border-radius: 999px; color: #477064; background: #eff7f4; font-size: .68rem; line-height: 1.25; }
    .label.diagnostic { border-color: #e2c89c; color: #7a5213; background: #fff8e9; }
    .example p { max-width: 680px; margin-bottom: 14px; }
    ul { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; margin: 0; padding: 0; list-style: none; }
    a { color: #087356; text-underline-offset: 3px; }
    li a { display: flex; justify-content: space-between; gap: 20px; padding: 11px 13px; border: 1px solid #c9d5d0; border-radius: 5px; background: #fff; text-decoration: none; }
    li a:hover, li a:focus-visible { border-color: #087356; background: #f1faf6; outline: none; }
    footer { padding-top: 26px; color: #66736d; font-size: .8rem; line-height: 1.6; }
    @media (max-width: 520px) {
      main { width: min(100% - 24px, 820px); padding-top: 36px; }
      ul { grid-template-columns: 1fr; }
      .example-heading { align-items: flex-start; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Funarch examples</h1>
      <p>Learn Plinth and Plutarch side by side with the paper's introductory program, complete Cardano validators, and paired compiler-error examples. Every link opens editable source in the browser.</p>
    </header>${collections}
    <footer>
      Source: <a href="https://github.com/SeungheonOh/plinth-plutarch-comparison">plinth-plutarch-comparison</a><br>
      Plain list: <a href="/playground-links.md">playground-links.md</a>
    </footer>
  </main>
</body>
</html>
`;

await mkdir("site", { recursive: true });
await writeFile("playground-links.md", markdown);
await writeFile("site/playground-links.md", markdown);
await writeFile("site/index.html", html);

console.log(`Generated ${linkedExamples.length * 2} playground links.`);
