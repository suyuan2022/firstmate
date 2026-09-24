#!/usr/bin/env bash
# tests/local/fm-agents-refresh.test.sh - the Pi post-compaction instruction
# refresh follows AGENTS.override.md (bin/local/fm-agents-refresh-lib.sh, a
# local mod registered in MODS.md).
#
# Two kinds of case:
# - Behavior: the real helper functions are lifted out of
#   bin/fm-session-start.sh (hash_file_sha256, agents_refresh_required,
#   section), the real local file is sourced on top the way the hook line does,
#   and the refresh is asked for exactly as a Pi compaction asks for it.
# - Drift guard: the local file replaces two upstream functions. Their upstream
#   bodies are pinned here by fingerprint, so an upstream change fails this test
#   until the local copies are re-checked against it and the pins updated.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

SESSION_START="$ROOT/bin/fm-session-start.sh"
LIB="$ROOT/bin/local/fm-agents-refresh-lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-agents-refresh)

upstream_function() { # <name>
  awk -v fn="$1" '$0 ~ "^"fn"\\(\\) *\\{"{f=1} f{print} f&&/^}/{exit}' "$SESSION_START"
}

upstream_start_hash_block() {
  awk '/^AGENTS_START_HASH=$/{f=1} f{print} f&&/^fi$/{exit}' "$SESSION_START"
}

fingerprint() { shasum -a 256 | cut -c1-64; }

# Pinned from upstream bin/fm-session-start.sh (kunchenguid/firstmate, merged
# into this fork 2026-09-24). Update only after re-checking the local file.
PIN_DRIFTED=0c995696c171690fab27cbbb08f0e7af1d8be12cdc419fdfd5ab2e4668e8eaf5
PIN_PRINT=d72abd5fec4b9282af34a04d3be1e658bf1177c1be179f7d965eebd83b70ca06
PIN_START=7214b8fb81d28095990eeda838208f7555a6fae808acea58746d50b353066d37

test_upstream_bodies_unchanged() {
  assert_equals "$PIN_DRIFTED" "$(upstream_function agents_baseline_drifted | fingerprint)" \
    "upstream agents_baseline_drifted changed; re-check bin/local/fm-agents-refresh-lib.sh against it, then update PIN_DRIFTED"
  assert_equals "$PIN_PRINT" "$(upstream_function print_agents_refresh_if_required | fingerprint)" \
    "upstream print_agents_refresh_if_required changed; re-check bin/local/fm-agents-refresh-lib.sh against it, then update PIN_PRINT"
  assert_equals "$PIN_START" "$(upstream_start_hash_block | fingerprint)" \
    "upstream AGENTS_START_HASH block changed; re-check bin/local/fm-agents-refresh-lib.sh against it, then update PIN_START"
  # shellcheck disable=SC2016 # the literal hook line, not an expansion
  assert_grep '. "$SCRIPT_DIR/local/fm-agents-refresh-lib.sh"' "$SESSION_START" \
    "the fm-session-start.sh hook line that loads the local file is gone"
  pass "the two replaced upstream functions and the start-hash block still match what the local file was written against"
}

# A home with an upstream AGENTS.md and, optionally, the trimmed contract
# behind an AGENTS.override.md symlink.
make_root() { # <name> <override:yes|no>
  local r="$TMP_ROOT/$1"
  mkdir -p "$r/state"
  printf 'UPSTREAM CONTRACT v1\n' > "$r/AGENTS.md"
  if [ "$2" = yes ]; then
    printf 'TRIMMED CONTRACT v1\n' > "$r/AGENTS.local.md"
    ln -s AGENTS.local.md "$r/AGENTS.override.md"
  fi
  printf '%s\n' "$r"
}

# Runs one session-start step in a fresh shell: `start` computes the
# true-start hash and records it as the baseline for pid 100; `compact <pid>`
# asks for the refresh a Pi compaction asks for.
run_step() { # <root> <start|compact> [pid]
  local r=$1 step=$2 pid=${3:-100}
  bash -c '
set -u
FM_ROOT=$1; STEP=$2; PID=$3
AGENTS_BASELINE_FILE="$FM_ROOT/state/.session-start-agents-baseline"
PRIMARY_HARNESS=pi SESSION_SOURCE=compact REEMIT=1
RULE="================================================================================"
eval "$4"
AGENTS_START_HASH=
if [ "$STEP" = start ]; then
  AGENTS_START_HASH=$(hash_file_sha256 "$FM_ROOT/AGENTS.md" 2>/dev/null || true)
fi
. "$5"
if [ "$STEP" = start ]; then
  printf "%s\n%s\n" 100 "$AGENTS_START_HASH" > "$AGENTS_BASELINE_FILE"
else
  print_agents_refresh_if_required "$PID"
fi
' _ "$r" "$step" "$pid" "$HELPERS" "$LIB"
}

HELPERS="$(upstream_function hash_file_sha256)
$(upstream_function agents_refresh_required)
$(upstream_function section)"

test_override_home_refreshes_only_on_trimmed_drift() {
  local r out
  r=$(make_root trimmed yes)
  run_step "$r" start
  out=$(run_step "$r" compact)
  assert_not_contains "$out" "INSTRUCTION REFRESH" \
    "an unchanged trimmed contract must not be reprinted after compaction"
  printf 'UPSTREAM CONTRACT v2\n' > "$r/AGENTS.md"
  out=$(run_step "$r" compact)
  assert_not_contains "$out" "INSTRUCTION REFRESH" \
    "an upstream AGENTS.md change that the loaded trimmed contract does not carry is not drift"
  printf 'TRIMMED CONTRACT v2\n' > "$r/AGENTS.local.md"
  out=$(run_step "$r" compact)
  assert_contains "$out" "CURRENT AGENTS.md - INSTRUCTION REFRESH" \
    "a changed trimmed contract must be reprinted after compaction"
  assert_contains "$out" "TRIMMED CONTRACT v2" "the refresh must print the trimmed contract Pi loads"
  assert_not_contains "$out" "UPSTREAM CONTRACT" "the refresh must not reprint the full upstream contract"
  assert_contains "$out" "AGENTS.override.md below" "the refresh must name the file it printed"
  pass "with AGENTS.override.md, the refresh fires on trimmed-contract drift and prints the trimmed contract"
}

test_unknown_start_prints_trimmed_contract() {
  local r out
  r=$(make_root foreign yes)
  run_step "$r" start
  out=$(run_step "$r" compact 200)
  assert_contains "$out" "TRIMMED CONTRACT v1" \
    "a compaction by a process that did not record the baseline must print the trimmed contract"
  assert_not_contains "$out" "UPSTREAM CONTRACT" \
    "a compaction by a process that did not record the baseline must not print the full upstream contract"
  pass "a refresh the baseline cannot rule out prints the trimmed contract, not the upstream one"
}

test_no_override_behaves_as_upstream() {
  local r out
  r=$(make_root plain no)
  run_step "$r" start
  out=$(run_step "$r" compact)
  assert_not_contains "$out" "INSTRUCTION REFRESH" "an unchanged AGENTS.md must not be reprinted"
  printf 'UPSTREAM CONTRACT v2\n' > "$r/AGENTS.md"
  out=$(run_step "$r" compact)
  assert_contains "$out" "UPSTREAM CONTRACT v2" "without an override a changed AGENTS.md must be reprinted"
  assert_contains "$out" "The complete on-disk AGENTS.md below supersedes" \
    "without an override the refresh wording must stay upstream's"
  pass "a home without AGENTS.override.md refreshes exactly as upstream does"
}

test_upstream_bodies_unchanged
test_override_home_refreshes_only_on_trimmed_drift
test_unknown_start_prints_trimmed_contract
test_no_override_behaves_as_upstream

echo "# all fm-agents-refresh tests passed"
