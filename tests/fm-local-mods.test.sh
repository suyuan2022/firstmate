#!/usr/bin/env bash
# tests/fm-local-mods.test.sh - run every local-mod test under tests/local/.
#
# A local mod, not part of upstream Firstmate: MODS.md registers it. The test
# runner (bin/fm-test-run.sh) discovers only tests/*.test.sh, so this one entry
# is how the local-mod tests reach --all, the CI shards, and the coverage guard
# without a hook in the runner or its own test. Each script runs in its own bash
# process in lexical order, its output is passed through, and the first failure
# fails this entry. An empty tests/local/ fails rather than passing vacuously.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ran=0
for script in "$ROOT"/tests/local/*.test.sh; do
  [ -f "$script" ] || continue
  printf '# --- tests/local/%s ---\n' "$(basename "$script")"
  bash "$script" || fail "tests/local/$(basename "$script") failed"
  ran=$((ran + 1))
done
[ "$ran" -gt 0 ] || fail "no tests found under tests/local/"
pass "all $ran local-mod test scripts under tests/local/ passed"
