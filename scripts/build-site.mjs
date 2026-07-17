#!/usr/bin/env node
// Renders the price-bearing templates in site/ into docs/, substituting {{tokens}}
// from site/site.config.json. docs/ is the deploy source (pages.yml rsyncs it to
// gh-pages), so the rendered files are committed; CI re-runs this and fails on drift.
// Change the price in site/site.config.json, run `just build-site`, commit.
//
// Only the templated HTML lives in site/. Everything else in docs/ (assets,
// privacy.html, robots.txt, sitemap.xml, CNAME) is hand-maintained there directly.

import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const siteDir = join(root, "site");
const docsDir = join(root, "docs");

const config = JSON.parse(readFileSync(join(siteDir, "site.config.json"), "utf8"));
// Derive the bare numeric amount (for the schema.org Offer) from the display price
// so the two can never drift; the config carries one price string, not two.
config.priceAmount = (config.price.match(/[\d.]+/) || [""])[0];
const templates = readdirSync(siteDir).filter((f) => f.endsWith(".html"));

const provenance = (name) =>
  `<!-- GENERATED from site/${name} by scripts/build-site.mjs. Do not edit here; edit the template and run \`just build-site\`. -->\n`;

let wrote = 0;
for (const name of templates) {
  const template = readFileSync(join(siteDir, name), "utf8");

  const rendered = template.replace(/\{\{\s*(\w+)\s*\}\}/g, (_, key) => {
    if (!(key in config)) throw new Error(`${name}: unknown token {{${key}}}; add it to site/site.config.json`);
    return config[key];
  });

  const out = rendered.replace(/^(<!doctype html>\n)/i, `$1${provenance(name)}`);
  writeFileSync(join(docsDir, name), out);
  wrote++;
}

console.log(`build-site: rendered ${wrote} page(s) from site/ → docs/`);
