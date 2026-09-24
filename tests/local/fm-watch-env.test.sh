#!/usr/bin/env bash
# tests/local/fm-watch-env.test.sh - home-local watcher timing from
# config/watch.env (bin/local/fm-watch-env-lib.sh plus its fm-watch.sh hook
# lines, a local mod registered in MODS.md).
#
# Every case sources the REAL bin/fm-watch.sh the way upstream's unit tests do
# (the source guard returns before the lock and the loop) in a fresh shell, with
# a scratch home whose config/watch.env the case writes, and prints the timing
# variables the watcher actually settled on.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-watch-env)

# watcher_timings <home> [VAR=value...]: prints
# "STALE_ESCALATE_SECS PAUSE_RESURFACE_SECS TURNEND_CHURN_ABSORB_SECS BUSY_TURN_MAX_SECS"
# and passes the watcher's stderr through.
watcher_timings() {
  local home=$1; shift
  mkdir -p "$home/state" "$home/config"
  env -u FM_PAUSE_RESURFACE_SECS -u FM_STALE_ESCALATE_SECS -u FM_TURNEND_CHURN_ABSORB_SECS \
    -u FM_BUSY_TURN_MAX_SECS -u FM_CONFIG_OVERRIDE \
    FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" "$@" bash -c '
. "$1/bin/fm-watch.sh"
printf "%s %s %s %s\n" "$STALE_ESCALATE_SECS" "$PAUSE_RESURFACE_SECS" "$TURNEND_CHURN_ABSORB_SECS" "$BUSY_TURN_MAX_SECS"
' _ "$ROOT"
}

test_absent_file_keeps_upstream_defaults() {
  local out
  out=$(watcher_timings "$TMP_ROOT/absent" 2>&1) || fail "sourcing the watcher failed: $out"
  assert_equals "240 14400 900 3600" "$out" "without config/watch.env the watcher must keep upstream's defaults"
  pass "an absent config/watch.env leaves every timing at upstream's default"
}

test_file_sets_supported_timings() {
  local home="$TMP_ROOT/set" out
  mkdir -p "$home/config"
  cat > "$home/config/watch.env" <<'EOF'
# watcher timing for this home
FM_PAUSE_RESURFACE_SECS=28800
  FM_STALE_ESCALATE_SECS=600  
EOF
  out=$(watcher_timings "$home" 2>&1) || fail "sourcing the watcher failed: $out"
  assert_equals "600 28800 900 3600" "$out" "config/watch.env values must reach the watcher's timing variables"
  pass "config/watch.env sets the watcher's wedge-escalation and declared-wait recheck timings"
}

test_environment_wins_over_file() {
  local home="$TMP_ROOT/env-wins" out
  mkdir -p "$home/config"
  printf 'FM_STALE_ESCALATE_SECS=600\n' > "$home/config/watch.env"
  out=$(watcher_timings "$home" FM_STALE_ESCALATE_SECS=300 2>&1) || fail "sourcing the watcher failed: $out"
  assert_equals "300 14400 900 3600" "$out" "a value already in the watcher's environment must win over the file"
  pass "an explicit environment value wins over config/watch.env"
}

test_bad_lines_warn_and_keep_defaults() {
  local home="$TMP_ROOT/bad" out timings
  mkdir -p "$home/config"
  cat > "$home/config/watch.env" <<'EOF'
FM_POLL=1
FM_STALE_ESCALATE_SECS=abc
FM_PAUSE_RESURFACE_SECS=0600
FM_BUSY_TURN_MAX_SECS
FM_TURNEND_CHURN_ABSORB_SECS=1200
EOF
  out=$(watcher_timings "$home" 2>&1) || fail "a broken config/watch.env must not stop the watcher: $out"
  timings=$(printf '%s\n' "$out" | tail -1)
  assert_equals "240 14400 1200 3600" "$timings" \
    "bad lines must keep their defaults while a good line in the same file still applies"
  assert_contains "$out" "line 1: 'FM_POLL' is not a supported key" "an unsupported key must be named"
  assert_contains "$out" "line 2: FM_STALE_ESCALATE_SECS must be a positive integer" "a non-number must be named"
  assert_contains "$out" "line 3: FM_PAUSE_RESURFACE_SECS must be a positive integer without a leading zero" \
    "a leading zero (read as octal by bash arithmetic) must be refused"
  assert_contains "$out" "line 4: expected KEY=VALUE" "a line without = must be named"
  pass "unsupported keys and bad values are skipped with a named warning; the watcher still starts"
}

test_absent_file_keeps_upstream_defaults
test_file_sets_supported_timings
test_environment_wins_over_file
test_bad_lines_warn_and_keep_defaults

echo "# all fm-watch-env tests passed"
