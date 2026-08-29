#!/usr/bin/env node

import { gunzipSync } from "node:zlib";
import { readFile } from "node:fs/promises";

const markdown = await readFile("playground-links.md", "utf8");
const urls = [...markdown.matchAll(/\((https:\/\/plinth\.isotopy\.xyz\/#p=z[^)]+)\)/g)].map(
  (match) => match[1],
);

if (urls.length !== 16) {
  throw new Error(`Expected 16 encoded playground links, found ${urls.length}`);
}

for (const [index, url] of urls.entries()) {
  const payload = new URL(url).hash.slice("#p=z".length);
  const project = JSON.parse(gunzipSync(Buffer.from(payload, "base64url")));
  const names = project.modules.map((module) => module.name);

  if (project.v !== 1 || project.active !== "Main.hs" || !names.includes("Main.hs")) {
    throw new Error(`Link ${index + 1} does not contain a valid version 1 project`);
  }
  if (new Set(names).size !== names.length) {
    throw new Error(`Link ${index + 1} contains duplicate module names`);
  }
  if (project.modules.some((module) => !module.name || !module.source)) {
    throw new Error(`Link ${index + 1} contains an empty module`);
  }
}

console.log(`Validated ${urls.length} encoded multi-module projects.`);
