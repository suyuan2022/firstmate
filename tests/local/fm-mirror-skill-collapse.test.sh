#!/usr/bin/env bash
# tests/local/fm-mirror-skill-collapse.test.sh - the supervision branch's
# main-dialog mirror collapses slash-command skill bodies
# (.pi/extensions/local-mirror-skill-collapse.ts plus one LOCAL hook line in
# .pi/extensions/fm-branch-supervision.ts, a local mod registered in MODS.md).
#
# The real extension file is loaded the way Pi loads it (import, call the
# default export) from a scratch checkout, with and without the home flag, and
# the installed function is fed the exact message shapes Pi produces. The hook
# line itself is asserted to read that function and to fall back to upstream's
# format, so an upstream edit that drops or reshapes the line fails here.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

command -v node >/dev/null 2>&1 || { echo "# skip: node not installed"; exit 0; }

TMP_ROOT=$(fm_test_tmproot fm-mirror-skill-collapse)
EXT="$ROOT/.pi/extensions/local-mirror-skill-collapse.ts"
BRANCH_EXT="$ROOT/.pi/extensions/fm-branch-supervision.ts"

make_checkout() { # <name> <flag:yes|no>
  local d="$TMP_ROOT/checkout-$1"
  mkdir -p "$d/.pi/extensions" "$d/config"
  cp "$EXT" "$d/.pi/extensions/local-mirror-skill-collapse.ts"
  [ "$2" = yes ] && : > "$d/config/branch-mirror-collapse-skills"
  printf '%s\n' "$d"
}

# Loads the extension from <checkout>, then prints what the hook line would
# send for each JSON-encoded [tag, text] pair, one JSON string per line.
mirror_contents() { # <checkout> <json-array-of-pairs>
  node --no-warnings --input-type=module -e "
const m = await import('file://$1/.pi/extensions/local-mirror-skill-collapse.ts');
m.default({});
const hook = globalThis.fmLocalMirrorContent;
for (const [tag, text] of JSON.parse(process.argv[1])) {
  const out = hook?.(tag, text) ?? \`[\${tag}] \${text}\`;
  console.log(JSON.stringify(out));
}
" "$2"
}

SKILL_WITH_WORDS='<skill name=\"afk\" location=\"/x/.agents/skills/afk/SKILL.md\">\nReferences are relative to /x/.agents/skills/afk.\n\n# afk\n\nLong body line one.\nLong body line two.\n</skill>\n\n我下楼散散步，十几分钟后回来'
SKILL_ALONE='<skill name=\"stow\" location=\"/x/.agents/skills/stow/SKILL.md\">\nReferences are relative to /x.\n\n# stow\nbody\n</skill>'
CAPPED='<skill name=\"bearings\" location=\"/x/SKILL.md\">\nhead of body\n[mirror truncated: 22712 characters omitted]\ntail of body\n</skill>\n\n什么带病，重新说'
PLAIN='普通的一句话，提到 <skill name=\"x\"> 也不算技能块'

test_flagged_home_collapses_skill_blocks() {
  local d out
  d=$(make_checkout on yes)
  out=$(mirror_contents "$d" "[[\"captain\",\"$SKILL_WITH_WORDS\"],[\"captain\",\"$SKILL_ALONE\"],[\"captain\",\"$CAPPED\"],[\"captain\",\"$PLAIN\"],[\"main\",\"$SKILL_ALONE\"]]") \
    || fail "the extension failed to load or run"
  assert_equals '"[captain] ran /afk\n\n我下楼散散步，十几分钟后回来"' "$(sed -n 1p <<<"$out")" \
    "a skill block with the captain's words must become one line plus those words"
  assert_equals '"[captain] ran /stow"' "$(sed -n 2p <<<"$out")" \
    "a bare skill block must become one line"
  assert_equals '"[captain] ran /bearings\n\n什么带病，重新说"' "$(sed -n 3p <<<"$out")" \
    "an older captain message the mirror already capped must collapse the same way"
  assert_contains "$(sed -n 4p <<<"$out")" '"[captain] 普通的一句话' \
    "ordinary captain text must be mirrored in upstream's format"
  assert_contains "$(sed -n 5p <<<"$out")" '"[main] <skill name=' \
    "main's own messages must never be rewritten"
  pass "a flagged home mirrors a skill command as one line plus the captain's own words, and nothing else changes"
}

test_unflagged_home_changes_nothing() {
  local d out
  d=$(make_checkout off no)
  out=$(mirror_contents "$d" "[[\"captain\",\"$SKILL_ALONE\"]]") || fail "the extension failed to load without the flag"
  assert_contains "$out" '"[captain] <skill name=\"stow\"' \
    "without config/branch-mirror-collapse-skills the mirror must stay upstream's"
  pass "without the flag the mirror is exactly upstream's"
}

test_hook_line_present() {
  assert_grep '(globalThis as { fmLocalMirrorContent?: (tag: string, text: string) => string }).fmLocalMirrorContent?.(item.tag, item.text) ?? `[${item.tag}] ${item.text}`' \
    "$BRANCH_EXT" \
    "the LOCAL hook line in fm-branch-supervision.ts's flushMirror is missing or reshaped"
  pass "fm-branch-supervision.ts still routes mirror content through the local hook with upstream's fallback"
}

test_flagged_home_collapses_skill_blocks
test_unflagged_home_changes_nothing
test_hook_line_present

echo "# all fm-mirror-skill-collapse tests passed"
