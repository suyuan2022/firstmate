// LOCAL: point chrome-devtools-axi at Chrome for Testing for a Pi session running in this home (MODS.md).
//
// bin/fm-spawn.sh already exports CHROME_DEVTOOLS_AXI_MCP_PATH into every pane it
// launches (bin/local/fm-spawn-setup-lib.sh spawn_local_pane_exports). The one
// agent it never launches is the primary itself, which the captain starts by
// hand. Pi runs every bash tool command with process.env, so setting the variable
// here when the extension loads gives the primary's own browser work the same
// Chrome for Testing as its crew.
//
// Gate: the home-local, gitignored presence flag config/chrome-devtools-cft in
// the checkout this file lives in, the same flag the spawn hook reads. Absent
// flag, missing shim, or a value already set in the environment: nothing
// changes. A worker whose worktree is a checkout of this repository has no
// config/ of its own, so the extension is a no-op there.
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export default function localChromeDevtoolsCft(): void {
  const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
  if (!existsSync(join(root, "config", "chrome-devtools-cft"))) return;
  if (process.env.CHROME_DEVTOOLS_AXI_MCP_PATH) return;
  const shim = join(root, "bin", "local", "chrome-devtools-mcp-cft.mjs");
  if (!existsSync(shim)) return;
  process.env.CHROME_DEVTOOLS_AXI_MCP_PATH = shim;
}
