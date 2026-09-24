#!/usr/bin/env bash
# tests/local/fm-chrome-devtools-mcp-cft.test.sh - the Chrome for Testing shim
# for chrome-devtools-axi (bin/local/chrome-devtools-mcp-cft.mjs, a local mod
# registered in MODS.md).
#
# Every case runs the real shim the way the axi bridge does (`node <shim>
# <args>`) against a fake chrome-devtools-mcp that prints the argv it received,
# with HOME pointed at a scratch directory so only the fake Chrome for Testing
# installs a case creates can be found. What is proved is the argv the real
# chrome-devtools-mcp would see, and that the shim never falls back to the
# user's everyday Chrome.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

command -v node >/dev/null 2>&1 || { echo "# skip: node not installed"; exit 0; }

TMP_ROOT=$(fm_test_tmproot fm-chrome-devtools-mcp-cft)
SHIM="$ROOT/bin/local/chrome-devtools-mcp-cft.mjs"
CFT_BIN='Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'
AB_REL=".agent-browser/browsers/chrome-mac-arm64/$CFT_BIN"

FAKE_MCP="$TMP_ROOT/fake-mcp.mjs"
cat > "$FAKE_MCP" <<'EOF'
console.log("MCP_ARGV " + JSON.stringify(process.argv.slice(2)));
EOF

make_home() { # <name>
  mkdir -p "$TMP_ROOT/$1"
  printf '%s\n' "$TMP_ROOT/$1"
}

fake_cft() { # <path>
  mkdir -p "$(dirname "$1")"
  : > "$1"
}

# Run the shim with a clean browser environment: only HOME and the variables a
# case names decide what it finds.
run_shim() { # <home> [VAR=value...] -- <args...>
  local home=$1; shift
  local envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  env -u FM_CFT_EXECUTABLE -u FM_CDM_REAL_MCP_PATH HOME="$home" \
    FM_CDM_REAL_MCP_PATH="$FAKE_MCP" "${envs[@]+"${envs[@]}"}" node "$SHIM" "$@"
}

test_launch_mode_appends_agent_browser_cft() {
  local home out
  home=$(make_home ab)
  fake_cft "$home/$AB_REL"
  out=$(run_shim "$home" -- --headless --isolated) || fail "shim failed in launch mode"
  assert_contains "$out" "MCP_ARGV [\"--headless\",\"--isolated\",\"--executablePath=$home/$AB_REL\"]" \
    "launch mode did not hand the real mcp the axi args plus the agent-browser Chrome for Testing"
  pass "launch mode appends --executablePath for the agent-browser Chrome for Testing"
}

test_override_and_newest_playwright_are_used() {
  local home out pw override
  home=$(make_home pw)
  pw="$home/Library/Caches/ms-playwright"
  fake_cft "$pw/chromium-999/chrome-mac-arm64/$CFT_BIN"
  fake_cft "$pw/chromium-1228/chrome-mac-arm64/$CFT_BIN"
  out=$(run_shim "$home" -- --headless) || fail "shim failed with only Playwright installs"
  assert_contains "$out" "--executablePath=$pw/chromium-1228/chrome-mac-arm64/$CFT_BIN" \
    "the numerically newest Playwright Chrome for Testing was not chosen"
  override="$TMP_ROOT/custom/chrome-for-testing"
  fake_cft "$override"
  out=$(run_shim "$home" FM_CFT_EXECUTABLE="$override" -- --headless) || fail "shim failed with FM_CFT_EXECUTABLE"
  assert_contains "$out" "--executablePath=$override\"" "FM_CFT_EXECUTABLE did not take precedence"
  pass "FM_CFT_EXECUTABLE wins, otherwise the numerically newest Playwright install is used"
}

test_attach_and_explicit_modes_pass_through() {
  local home out args
  home=$(make_home attach)
  fake_cft "$home/$AB_REL"
  for args in "--browserUrl=http://127.0.0.1:9222" "--wsEndpoint=ws://x" "--autoConnect" "--channel=canary" "--executablePath=/x/chrome"; do
    out=$(run_shim "$home" -- "$args") || fail "shim failed for $args"
    assert_equals "MCP_ARGV [\"$args\"]" "$out" "$args was not passed through unchanged"
  done
  pass "attach modes and explicit browser choices pass through unchanged"
}

test_missing_cft_refuses_instead_of_everyday_chrome() {
  local home out rc=0
  home=$(make_home none)
  out=$(run_shim "$home" -- --headless 2>&1) || rc=$?
  expect_code 1 "$rc" "missing Chrome for Testing"
  assert_contains "$out" "no Chrome for Testing found" "the refusal did not say why"
  assert_not_contains "$out" "MCP_ARGV" "the real mcp still ran without a Chrome for Testing"
  pass "with no Chrome for Testing the shim refuses rather than launching everyday Chrome"
}

test_missing_real_mcp_refuses() {
  local home out rc=0
  home=$(make_home no-mcp)
  fake_cft "$home/$AB_REL"
  out=$(run_shim "$home" FM_CDM_REAL_MCP_PATH="$TMP_ROOT/absent.js" -- --headless 2>&1) || rc=$?
  expect_code 1 "$rc" "missing real chrome-devtools-mcp"
  assert_contains "$out" "real chrome-devtools-mcp not found" "the refusal did not name the missing mcp"
  pass "a missing real chrome-devtools-mcp is a clear refusal, not a stack trace"
}

# The shim only works while axi still honours CHROME_DEVTOOLS_AXI_MCP_PATH.
# Checked against the locally bootstrapped axi when there is one (not in CI).
test_installed_axi_still_honours_mcp_path() {
  local bridge="$ROOT/.tools/node_modules/chrome-devtools-axi/dist/src/bridge.js"
  if [ ! -f "$bridge" ]; then
    echo "# skip: no bootstrapped chrome-devtools-axi under .tools"
    return 0
  fi
  assert_grep "CHROME_DEVTOOLS_AXI_MCP_PATH" "$bridge" \
    "the installed chrome-devtools-axi no longer reads CHROME_DEVTOOLS_AXI_MCP_PATH; the shim is dead"
  pass "the bootstrapped chrome-devtools-axi still reads CHROME_DEVTOOLS_AXI_MCP_PATH"
}

# The primary's own Pi session gets the variable from
# .pi/extensions/local-chrome-devtools-cft.ts. Each case lays out a scratch
# checkout (extension, shim, optional flag) and loads the real extension file
# the way Pi does - import, then call the default export - in a fresh node
# process, printing what the bash tool environment would carry.
EXT="$ROOT/.pi/extensions/local-chrome-devtools-cft.ts"

make_checkout() { # <name> <flag:yes|no> <shim:yes|no>
  local d="$TMP_ROOT/checkout-$1"
  mkdir -p "$d/.pi/extensions" "$d/bin/local" "$d/config"
  cp "$EXT" "$d/.pi/extensions/local-chrome-devtools-cft.ts"
  [ "$3" = yes ] && : > "$d/bin/local/chrome-devtools-mcp-cft.mjs"
  [ "$2" = yes ] && : > "$d/config/chrome-devtools-cft"
  printf '%s\n' "$d"
}

load_extension() { # <checkout> [VAR=value...]
  local d=$1; shift
  env -u CHROME_DEVTOOLS_AXI_MCP_PATH "$@" node --no-warnings --input-type=module -e "
const m = await import('file://$d/.pi/extensions/local-chrome-devtools-cft.ts');
m.default({});
console.log(process.env.CHROME_DEVTOOLS_AXI_MCP_PATH ?? 'unset');
"
}

test_pi_extension_sets_path_only_when_flagged() {
  local d out
  d=$(make_checkout on yes yes)
  out=$(load_extension "$d") || fail "extension failed to load with the flag set"
  assert_equals "$d/bin/local/chrome-devtools-mcp-cft.mjs" "$out" \
    "with the flag set the extension must point axi at this checkout's shim"
  d=$(make_checkout off no yes)
  out=$(load_extension "$d") || fail "extension failed to load without the flag"
  assert_equals unset "$out" "without config/chrome-devtools-cft the extension must change nothing"
  d=$(make_checkout noshim yes no)
  out=$(load_extension "$d") || fail "extension failed to load without the shim"
  assert_equals unset "$out" "a flag whose shim is missing must not point axi at a missing file"
  d=$(make_checkout preset yes yes)
  out=$(load_extension "$d" CHROME_DEVTOOLS_AXI_MCP_PATH=/already/set.mjs) || fail "extension failed with a preset value"
  assert_equals /already/set.mjs "$out" "a value already in the environment must win"
  pass "the Pi extension sets CHROME_DEVTOOLS_AXI_MCP_PATH only for a flagged home with a shim and no preset value"
}

test_launch_mode_appends_agent_browser_cft
test_override_and_newest_playwright_are_used
test_attach_and_explicit_modes_pass_through
test_missing_cft_refuses_instead_of_everyday_chrome
test_missing_real_mcp_refuses
test_installed_axi_still_honours_mcp_path
test_pi_extension_sets_path_only_when_flagged

echo "# all fm-chrome-devtools-mcp-cft tests passed"
