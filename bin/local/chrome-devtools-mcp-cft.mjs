#!/usr/bin/env node
// LOCAL: make chrome-devtools-axi launch Chrome for Testing instead of the user's everyday Chrome.
//
// Why: chrome-devtools-axi launches chrome-devtools-mcp, which by default starts a headless
// copy of /Applications/Google Chrome.app. macOS then treats that invisible instance as "the"
// running Chrome, and clicking the Dock icon only re-activates it, so the user's Chrome
// appears not to open. axi does not expose --executablePath, but it does let
// CHROME_DEVTOOLS_AXI_MCP_PATH point at any script it runs as `node <script> <args>`.
// This file is that script: it appends --executablePath=<Chrome for Testing> and hands off
// to the real chrome-devtools-mcp.
//
// Enable (machine-wide, e.g. ~/.zshenv):
//   export CHROME_DEVTOOLS_AXI_MCP_PATH="$HOME/firstmate/bin/local/chrome-devtools-mcp-cft.mjs"
// Optional overrides:
//   FM_CFT_EXECUTABLE     path to a Chrome for Testing binary
//   FM_CDM_REAL_MCP_PATH  path to the real chrome-devtools-mcp.js
import { existsSync, readdirSync } from "node:fs";
import { execSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const CFT_BIN = "Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";

function findCft() {
  const candidates = [];
  if (process.env.FM_CFT_EXECUTABLE) candidates.push(process.env.FM_CFT_EXECUTABLE);
  candidates.push(join(homedir(), ".agent-browser/browsers/chrome-mac-arm64", CFT_BIN));
  const pw = join(homedir(), "Library/Caches/ms-playwright");
  if (existsSync(pw)) {
    const newestFirst = readdirSync(pw)
      .filter((d) => /^chromium-\d+$/.test(d))
      .sort((a, b) => Number(b.slice(9)) - Number(a.slice(9)));
    for (const dir of newestFirst) {
      candidates.push(join(pw, dir, "chrome-mac-arm64", CFT_BIN));
    }
  }
  return candidates.find((p) => existsSync(p)) ?? null;
}

function findRealMcp() {
  const override = process.env.FM_CDM_REAL_MCP_PATH;
  if (override) return existsSync(override) ? override : null;
  let prefix = "";
  try {
    prefix = execSync("npm prefix -g", { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {}
  const p = join(prefix, "lib/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js");
  return prefix && existsSync(p) ? p : null;
}

const args = process.argv.slice(2);
// Attach modes and explicit browser choices conflict with --executablePath; leave them alone.
const attachOrExplicit = args.some((a) =>
  /^(--(browserUrl|wsEndpoint|autoConnect|channel|executablePath)|-e)(=|$)/.test(a),
);

const realMcp = findRealMcp();
if (!realMcp) {
  console.error("chrome-devtools-mcp-cft: real chrome-devtools-mcp not found; run `npm install -g chrome-devtools-mcp` or set FM_CDM_REAL_MCP_PATH");
  process.exit(1);
}

if (!attachOrExplicit) {
  const cft = findCft();
  if (!cft) {
    // Refuse rather than silently fall back to the user's everyday Chrome.
    console.error("chrome-devtools-mcp-cft: no Chrome for Testing found; run `agent-browser install` or `npx @puppeteer/browsers install chrome@stable`, or set FM_CFT_EXECUTABLE");
    process.exit(1);
  }
  args.push(`--executablePath=${cft}`);
}

process.argv = [process.argv[0], realMcp, ...args];
await import(pathToFileURL(realMcp).href);
