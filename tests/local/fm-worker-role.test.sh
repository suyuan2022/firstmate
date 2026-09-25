#!/usr/bin/env bash
# tests/local/fm-worker-role.test.sh - the local worker role addendum
# (bin/local/fm-worker-role-lib.sh plus two LOCAL hook lines in
# bin/fm-dod-lib.sh, a local mod registered in MODS.md).
#
# Renders the real role contract through fm_brief_worker_role and checks that
# the addendum sits right after the upstream sentence it qualifies, that the
# upstream sentence itself is unchanged (so the protection against a worker
# taking the supervisor identity still reads in full), and that the steering
# inbox line still follows.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

test_addendum_follows_the_upstream_sentence() {
  local out upstream_line addendum_line inbox_line
  out=$(bash -c '. "$1/bin/fm-timeout-lib.sh"; . "$1/bin/fm-dod-lib.sh"; fm_brief_worker_role /state task-1' _ "$ROOT") \
    || fail "fm_brief_worker_role failed"
  upstream_line=$(printf '%s\n' "$out" | grep -n '^Do the assigned work yourself and report only to firstmate; do not adopt a firstmate or secondmate supervisor identity, delegate the task, run fleet supervision, or address the captain\.$' | cut -d: -f1)
  addendum_line=$(printf '%s\n' "$out" | grep -n '^Exception in this home: text typed into your own window' | cut -d: -f1)
  # shellcheck disable=SC2016 # Backticks are literal role-contract Markdown.
  inbox_line=$(printf '%s\n' "$out" | grep -n '^Your steering inbox is `/state/task-1.inbox`' | cut -d: -f1)
  [ -n "$upstream_line" ] || fail "the upstream role sentence changed or is missing"
  [ -n "$addendum_line" ] || fail "the local addendum is missing from the role contract"
  [ "$addendum_line" -eq $((upstream_line + 1)) ] || fail "the addendum does not directly follow the sentence it qualifies"
  [ "$inbox_line" -eq $((addendum_line + 1)) ] || fail "the steering inbox line no longer follows the addendum"
  [ "$(printf '%s\n' "$out" | head -n 1)" = '# Current worker role contract' ] || fail "the role contract lost its heading"
  assert_contains "$out" "keep reporting status and results only to firstmate" "the addendum no longer keeps reporting with firstmate"
  pass "the worker role contract keeps upstream's sentence and adds the captain-window exception right after it"
}

test_addendum_follows_the_upstream_sentence

echo "# all fm-worker-role tests passed"
