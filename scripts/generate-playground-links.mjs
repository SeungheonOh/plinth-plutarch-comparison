#!/usr/bin/env node

import { gzipSync } from "node:zlib";
import { mkdir, readFile, writeFile } from "node:fs/promises";

const playgroundOrigin = "https://plinth.isotopy.xyz/";

const examples = [
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

async function projectFor(example, language) {
  const implementation = example[language];
  const modules = [
    {
      name: "Main.hs",
      source:
        language === "plutarch"
          ? plutarchMain(example, implementation)
          : plinthMain(implementation),
    },
  ];

  for (const sourcePath of implementation.files) {
    modules.push({
      name: moduleFilename(sourcePath),
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
    plinthUrl: projectUrl(await projectFor(example, "plinth")),
    plutarchUrl: projectUrl(await projectFor(example, "plutarch")),
  });
}

const markdown = [
  "# Funarch playground examples",
  "",
  "Each link opens a complete multi-module project in [Plinth Playground](https://plinth.isotopy.xyz/) with the source loaded and ready to compile.",
  "",
  ...linkedExamples.flatMap((example) => [
    `## ${example.title}`,
    "",
    `- [Open the Plinth implementation](${example.plinthUrl})`,
    `- [Open the Plutarch implementation](${example.plutarchUrl})`,
    "",
  ]),
].join("\n");

const cards = linkedExamples
  .map(
    (example) => `
      <section>
        <h2>${escapeHtml(example.title)}</h2>
        <p>${escapeHtml(example.description)}</p>
        <ul>
          <li><a href="${escapeHtml(example.plinthUrl)}">Open the Plinth implementation <span aria-hidden="true">→</span></a></li>
          <li><a href="${escapeHtml(example.plutarchUrl)}">Open the Plutarch implementation <span aria-hidden="true">→</span></a></li>
        </ul>
      </section>`,
  )
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
    main { width: min(760px, calc(100% - 32px)); margin: 0 auto; padding: 64px 0 80px; }
    header { padding-bottom: 28px; border-bottom: 1px solid #ced8d3; }
    h1 { margin: 0 0 12px; font: 700 clamp(2rem, 7vw, 3.5rem)/1.04 ui-sans-serif, system-ui, sans-serif; letter-spacing: -0.055em; }
    header p { max-width: 650px; margin: 0; color: #55635d; line-height: 1.65; }
    section { padding: 27px 0 24px; border-bottom: 1px solid #dbe2df; }
    h2 { margin: 0 0 8px; font: 650 1.08rem/1.4 ui-sans-serif, system-ui, sans-serif; letter-spacing: -0.015em; }
    section p { margin: 0 0 15px; color: #66736d; font-size: .86rem; line-height: 1.55; }
    ul { display: grid; gap: 8px; margin: 0; padding: 0; list-style: none; }
    a { color: #087356; text-underline-offset: 3px; }
    li a { display: flex; justify-content: space-between; gap: 20px; padding: 11px 13px; border: 1px solid #c9d5d0; border-radius: 5px; background: #fff; text-decoration: none; }
    li a:hover, li a:focus-visible { border-color: #087356; background: #f1faf6; outline: none; }
    footer { padding-top: 26px; color: #66736d; font-size: .8rem; line-height: 1.6; }
    @media (max-width: 520px) { main { width: min(100% - 24px, 760px); padding-top: 36px; } }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>Funarch examples</h1>
      <p>Plinth and Plutarch implementations of eight Cardano validators. Choose an implementation to open its complete multi-module source in Plinth Playground, ready to compile in your browser.</p>
    </header>${cards}
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
