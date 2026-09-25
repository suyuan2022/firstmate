#!/usr/bin/env bash
# tests/local/fm-agents-trim.test.sh - the trimmed supervisor contract generator
# (bin/local/fm-agents-trim.sh, a local mod registered in MODS.md).
#
# Every case runs the real script against the repository's AGENTS.md or an
# edited copy of it, so what is proved is what a run after an upstream merge
# does: every listed passage is found and only whole listed lines go, a passage
# the upstream text no longer carries stops the run without writing, and
# --check tells a current AGENTS.local.md from a stale one. The committed
# AGENTS.local.md is also held to the current AGENTS.md, so an upstream merge
# that skipped the re-run fails here.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

TRIM="$ROOT/bin/local/fm-agents-trim.sh"
TMP_ROOT=$(fm_test_tmproot fm-agents-trim)

# How every line the REPLACEMENTS list writes begins; nothing else may be new.
# shellcheck disable=SC2016 # Backticks are literal AGENTS.md Markdown.
REPLACED=(
  'Address the user in Chinese as '
  "Reply language and layout follow this home's captain preferences "
  'Bring these to the captain, timed by the three tiers '
  'Only the '
  'When the captain settles into one thing '
  'When he stops, clearly changes topic, '
  'Held items are never dropped: '
  'Reply exactly `'
  'For a captain-requested completion, '
)

# Lines that start with the given text, counted the way the script anchors them.
count_starting() { # <file> <leading text>
  awk -v p="$2" 'index($0, p) == 1 { n++ } END { print n + 0 }' "$1"
}

test_every_passage_is_found_and_only_listed_lines_go() {
  local out="$TMP_ROOT/found.md" gone
  "$TRIM" --source "$ROOT/AGENTS.md" --output "$out" >/dev/null \
    || fail "the script refused the repository's own AGENTS.md"
  # shellcheck disable=SC2016 # Backticks are literal AGENTS.md Markdown.
  for gone in '## 14. Relay' 'Relay may require that same live cycle' \
    'When Relay-linked work reaches a milestone' '- `fmx-respond` - ' \
    'config/x-mode.env ' '  x-watch.check.sh ' '  x-inbox/ ' '  x-context/ ' '  x-outbox/ ' \
    '  public-followup/ ' '  x-poll.error ' '  <id>.grok-turnend-token ' '  <id>.kimi-turnend-token ' \
    '  <id>.gemini-settings.json ' '  <id>.muse-session ' '  <id>.cursor-session ' \
    '  .cursor-park-owner ' 'config/cmux-socket-password ' '  mail.check.sh ' '  .mail-seen ' \
    '- `firstmate-orca` - ' '- `firstmate-codexapp` - ' \
    'Firstmate alone resolves a matched profile array' 'Load `quota-array-dispatch` ' \
    '- `quota-array-dispatch` - '; do
    [ "$(count_starting "$ROOT/AGENTS.md" "$gone")" -ge 1 ] || fail "fixture drift: AGENTS.md has no line starting '$gone'"
    [ "$(count_starting "$out" "$gone")" -eq 0 ] || fail "a listed passage survived the trim: '$gone'"
  done
  case "$(head -n 1 "$out")" in
    '<!-- LOCAL: '*) ;;
    *) fail "the generated file does not open with its LOCAL marker line" ;;
  esac
  # Only whole lines are removed: apart from the listed replacements, every
  # remaining line is an AGENTS.md line in its original order, and nothing
  # about no-mistakes is lost.
  local line prefix known
  while IFS= read -r line; do
    known=0
    [ -n "$line" ] || known=1
    for prefix in "${REPLACED[@]}"; do
      [ "${line#"$prefix"}" != "$line" ] && known=1
    done
    [ "$known" -eq 1 ] || fail "the generated file carries a line AGENTS.md does not and no replacement names: $line"
  done < <(diff <(tail -n +2 "$out") "$ROOT/AGENTS.md" | sed -n 's/^< //p')
  [ "$(grep -c 'no-mistakes' "$out")" -eq "$(grep -c 'no-mistakes' "$ROOT/AGENTS.md")" ] \
    || fail "a line mentioning no-mistakes was removed"
  pass "every listed passage is found and removed as whole lines, keeping everything about no-mistakes"
}

test_committed_trim_is_current() {
  local out
  out=$("$TRIM" --check 2>&1) || fail "the committed AGENTS.local.md is stale against AGENTS.md; run bin/local/fm-agents-trim.sh"$'\n'"$out"
  pass "the committed AGENTS.local.md matches what the current AGENTS.md generates"
}

# Run the script on an edited AGENTS.md copy whose output already holds a
# sentinel, and require a refusal that names the passage and writes nothing.
expect_refusal() { # <case> <edited source> <expected text> <label>
  local out="$TMP_ROOT/$1.out" err rc=0
  printf 'sentinel\n' > "$out"
  err=$("$TRIM" --source "$2" --output "$out" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 1 ] || fail "$4: expected exit 1, got $rc"$'\n'"$err"
  assert_contains "$err" "$3" "$4: the refusal did not name the passage"
  assert_contains "$err" "nothing was written" "$4: the refusal did not say nothing was written"
  [ "$(cat "$out")" = sentinel ] || fail "$4: the output file was written despite the refusal"
}

test_a_passage_upstream_no_longer_carries_stops_the_run() {
  local missing="$TMP_ROOT/missing.md" doubled="$TMP_ROOT/doubled.md" longer="$TMP_ROOT/longer.md"
  awk 'index($0, "- `quota-array-dispatch` - ") != 1' "$ROOT/AGENTS.md" > "$missing"
  expect_refusal missing "$missing" "- \`quota-array-dispatch\` - ': found 0 times" "a missing line"
  awk '{ print } index($0, "  x-inbox/ ") == 1 { print }' "$ROOT/AGENTS.md" > "$doubled"
  expect_refusal doubled "$doubled" "  x-inbox/ ': found 2 times" "an ambiguous line"
  awk '{ print } index($0, "Firstmate alone resolves a matched profile array") == 1 { print "An inserted upstream sentence." }' \
    "$ROOT/AGENTS.md" > "$longer"
  expect_refusal longer "$longer" "spans 11 lines (expected 10)" "a range that changed length"
  pass "a missing, ambiguous, or resized passage stops the run, names it, and writes nothing"
}

test_replacements_swap_in_the_local_wording_and_stop_on_upstream_change() {
  local out="$TMP_ROOT/replaced.md" changed="$TMP_ROOT/changed.md" gone
  "$TRIM" --source "$ROOT/AGENTS.md" --output "$out" >/dev/null || fail "could not generate the replacement fixture"
  # shellcheck disable=SC2016 # Backticks are literal AGENTS.md Markdown.
  for gone in 'Address the user as "captain" at least once' 'This is mandatory respectful address' \
    'Use light nautical seasoning' 'Reach the captain immediately for:' 'Reply exactly `Captain, shipshape.`'; do
    [ "$(count_starting "$ROOT/AGENTS.md" "$gone")" -eq 1 ] || fail "fixture drift: AGENTS.md has no line starting '$gone'"
    [ "$(count_starting "$out" "$gone")" -eq 0 ] || fail "a replaced line survived: '$gone'"
  done
  [ "$(grep -c 'Captain, shipshape' "$out")" -eq 0 ] || fail "the English no-op reply survived"
  [ "$(count_starting "$out" 'When the captain settles into one thing ')" -eq 1 ] || fail "the focus rule is missing"
  [ "$(count_starting "$out" '- Work ready for their review, with the PR')" -eq 1 ] || fail "the section 9 list lost an item"
  awk '{ sub(/This is mandatory respectful address, not performance/, "This is mandatory address"); print }' \
    "$ROOT/AGENTS.md" > "$changed"
  expect_refusal changed "$changed" "replacement in 'preamble' starting 'Address the user as" "a replaced line upstream reworded"
  pass "the replacements swap in the local wording and stop the run when upstream rewords a replaced line"
}

test_check_tells_current_from_stale() {
  local out="$TMP_ROOT/check.md" err rc=0 before
  "$TRIM" --source "$ROOT/AGENTS.md" --output "$out" >/dev/null || fail "could not generate the check fixture"
  "$TRIM" --check --source "$ROOT/AGENTS.md" --output "$out" >/dev/null \
    || fail "--check rejected a file the script had just generated"
  printf 'a hand edit\n' >> "$out"
  before=$(cat "$out")
  err=$("$TRIM" --check --source "$ROOT/AGENTS.md" --output "$out" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 1 ] || fail "--check accepted a drifted file (exit $rc)"
  assert_contains "$err" "does not match" "--check did not report the drift"
  assert_contains "$err" "+++ generated" "--check did not show how the file differs"
  [ "$(cat "$out")" = "$before" ] || fail "--check rewrote the file it was only asked to check"
  rc=0
  err=$("$TRIM" --check --source "$ROOT/AGENTS.md" --output "$TMP_ROOT/absent.md" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 1 ] || fail "--check accepted a missing file (exit $rc)"
  assert_contains "$err" "is missing" "--check did not report the missing file"
  pass "--check accepts a current file and reports a drifted or missing one without writing"
}

test_every_passage_is_found_and_only_listed_lines_go
test_committed_trim_is_current
test_a_passage_upstream_no_longer_carries_stops_the_run
test_replacements_swap_in_the_local_wording_and_stop_on_upstream_change
test_check_tells_current_from_stale

echo "# all fm-agents-trim tests passed"
