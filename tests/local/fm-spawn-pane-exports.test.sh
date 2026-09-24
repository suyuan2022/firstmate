#!/usr/bin/env bash
# tests/local/fm-spawn-pane-exports.test.sh - the home-local pane exports
# bin/fm-spawn.sh sends before it launches an agent
# (spawn_local_pane_exports in bin/local/fm-spawn-setup-lib.sh, a local mod
# registered in MODS.md).
#
# Every case drives the REAL fm-spawn against a fake pane and a real git
# worktree and reads the pane log, which is what the agent's shell received
# before the launch command. Then it replays those exports plus the launch
# under a probe harness, so what is proved is the environment a real agent
# would have started with.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures.sh"

TMP_ROOT=$(fm_test_tmproot fm-spawn-pane-exports)
SHIM="$ROOT/bin/local/chrome-devtools-mcp-cft.mjs"

# make_case <name> <harness> <id>
# Echoes "<case-dir>|<home>|<project>|<worktree>|<fakebin>|<launch-log>|<pane-log>".
make_case() {
  local name=$1 harness=$2 id=$3 case_dir home proj wt fakebin
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakebin=$(fm_test_make_spawn_fakebin "$case_dir/fake")
  fm_test_spawn_home "$home" "$harness"
  fm_git_worktree "$proj" "$wt" "wt-$name"
  fm_test_spawn_brief "$home" "$id"
  printf '%s\n' "$case_dir|$home|$proj|$wt|$fakebin|$case_dir/launch.log|$case_dir/pane.log"
}

read_case() {
  IFS='|' read -r CASE_DIR HOME_DIR PROJ_DIR WT_DIR FAKEBIN_DIR LAUNCH_LOG PANE_LOG <<EOF
$1
EOF
}

run_case_spawn() {
  : > "$LAUNCH_LOG"
  : > "$PANE_LOG"
  FM_FAKE_LAUNCH_LOG="$LAUNCH_LOG" FM_FAKE_PANE_LOG="$PANE_LOG" \
    fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$@"
}

# The harness binary becomes a probe that prints the one fact under test.
install_env_probe() { # <fakebin> <harness>
  cat > "$1/$2" <<'SH'
#!/bin/sh
printf '%s\n' "${CHROME_DEVTOOLS_AXI_MCP_PATH-unset}"
SH
  chmod +x "$1/$2"
}

# Replay the pane exports and the launch in a synthetic pane shell, in the
# order the real pane runs them.
emitted_env() {
  local preamble launch
  preamble=$(grep '^export ' "$PANE_LOG")
  launch=$(cat "$LAUNCH_LOG")
  env -i HOME="$TMP_ROOT/pane-home" PATH="$FAKEBIN_DIR:$PATH" TERM=xterm TMUX=synthetic-pane \
    /bin/sh -c "$preamble
$launch"
}

export_lines() { grep -c '^export CHROME_DEVTOOLS_AXI_MCP_PATH=' "$PANE_LOG" || true; }

test_flag_absent_sends_nothing() {
  local rec out status seen
  rec=$(make_case absent codex pane-absent-a1)
  read_case "$rec"
  out=$(run_case_spawn pane-absent-a1 "$PROJ_DIR" --mode no-mistakes --yolo off)
  status=$?
  expect_code 0 "$status" "spawn without the flag should succeed: $out"
  assert_equals 0 "$(export_lines)" "without config/chrome-devtools-cft the pane must not receive the axi export"
  install_env_probe "$FAKEBIN_DIR" codex
  seen=$(emitted_env) || fail "the emitted launch failed to run"
  assert_equals unset "$seen" "without the flag the agent must start without CHROME_DEVTOOLS_AXI_MCP_PATH"
  pass "an unflagged home launches exactly as upstream does"
}

test_flag_present_exports_shim_before_launch() {
  local rec out status seen gotmp axi
  rec=$(make_case present codex pane-present-a1)
  read_case "$rec"
  : > "$HOME_DIR/config/chrome-devtools-cft"
  out=$(run_case_spawn pane-present-a1 "$PROJ_DIR" --mode no-mistakes --yolo off)
  status=$?
  expect_code 0 "$status" "spawn with the flag should succeed: $out"
  assert_equals 1 "$(export_lines)" "a flagged home must send exactly one axi export"
  gotmp=$(grep -n '^export GOTMPDIR=' "$PANE_LOG" | tail -1 | cut -d: -f1)
  axi=$(grep -n '^export CHROME_DEVTOOLS_AXI_MCP_PATH=' "$PANE_LOG" | tail -1 | cut -d: -f1)
  [ -n "$gotmp" ] && [ -n "$axi" ] && [ "$axi" -gt "$gotmp" ] \
    || fail "the axi export must ride the GOTMPDIR pre-launch site (gotmp=$gotmp axi=$axi)"
  install_env_probe "$FAKEBIN_DIR" codex
  seen=$(emitted_env) || fail "the emitted launch failed to run"
  assert_equals "$SHIM" "$seen" "a flagged home's agent must start with axi pointed at this checkout's shim"
  pass "a flagged home exports the Chrome for Testing shim into the pane before launch"
}

test_secondmate_gets_the_export() {
  local rec sm out status seen
  rec=$(make_case secondmate codex sm-pane-a1)
  read_case "$rec"
  : > "$HOME_DIR/config/chrome-devtools-cft"
  sm="$CASE_DIR/secondmate-home"
  mkdir -p "$sm/bin" "$sm/data"
  printf '# Firstmate\n' > "$sm/AGENTS.md"
  printf '%s\n' sm-pane-a1 > "$sm/.fm-secondmate-home"
  printf 'charter for sm-pane-a1\n' > "$sm/data/charter.md"
  out=$(run_case_spawn sm-pane-a1 "$sm" --secondmate)
  status=$?
  expect_code 0 "$status" "secondmate spawn with the flag should succeed: $out"
  install_env_probe "$FAKEBIN_DIR" codex
  seen=$(emitted_env) || fail "the emitted secondmate launch failed to run"
  assert_equals "$SHIM" "$seen" "a secondmate launched from a flagged home must start with axi pointed at the shim"
  pass "a secondmate launch from a flagged home carries the axi export"
}

test_flag_absent_sends_nothing
test_flag_present_exports_shim_before_launch
test_secondmate_gets_the_export

echo "# all fm-spawn-pane-exports tests passed"
