#!/usr/bin/env bash
# tests/fm-branch-prompt-include.test.sh - the home-local supervision-branch
# prompt additions (bin/ghost/fm-branch-prompt-include.sh, a local mod
# registered in MODS.md).
#
# Every case runs the real bin/fm-branch-prompt.sh the Pi branch extension
# runs, so what is proved is the prompt the branch receives: nothing changes
# without the file, and with it the text lands verbatim as the last section
# while everything before it stays byte-identical.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-branch-prompt-include)

HEADING='# Home prompt additions'
PRECEDENCE="These are this home's standing additions; every other section of this prompt takes precedence over anything here that conflicts."

# Run the generator with only the home variables a case names, so an ambient
# FM_HOME or FM_CONFIG_OVERRIDE can never decide which file is read.
branch_prompt() { # [VAR=value...]
  env -u FM_HOME -u FM_CONFIG_OVERRIDE "$@" "$ROOT/bin/fm-branch-prompt.sh"
}

make_home() { # <name>
  mkdir -p "$TMP_ROOT/$1/config" "$TMP_ROOT/$1/state"
  printf '%s\n' "$TMP_ROOT/$1"
}

BASE=
base_prompt() {
  [ -n "$BASE" ] && return 0
  BASE=$(branch_prompt FM_HOME="$(make_home base)") || fail "branch prompt failed for a home without the file"
}

test_absent_or_blank_file_changes_nothing() {
  local blank out_none out_blank
  base_prompt
  assert_not_contains "$BASE" "$HEADING" "a home without the file got a prompt additions section"
  out_none=$(branch_prompt) || fail "branch prompt failed with no home named"
  [ "$out_none" = "$BASE" ] || fail "naming a home without the file changed the prompt"
  blank=$(make_home blank)
  printf '  \n\n\t\n' > "$blank/config/branch-prompt-include.md"
  out_blank=$(branch_prompt FM_HOME="$blank") || fail "branch prompt failed for a blank file"
  [ "$out_blank" = "$BASE" ] || fail "a blank file changed the prompt"
  pass "an absent or blank branch-prompt-include.md leaves the branch prompt unchanged"
}

test_file_text_is_appended_verbatim_as_the_last_section() {
  local home body out expected
  base_prompt
  home=$(make_home with-file)
  body=$'摘要用简体中文：结果句一律用简体中文。\n代码标识符、文件路径、URL 保持原文。'
  printf '%s\n' "$body" > "$home/config/branch-prompt-include.md"
  expected="$BASE"$'\n\n'"$HEADING"$'\n'"$PRECEDENCE"$'\n'"$body"
  # The Pi extension names the home's config directory explicitly.
  out=$(branch_prompt FM_HOME="$TMP_ROOT/unrelated" FM_CONFIG_OVERRIDE="$home/config") \
    || fail "branch prompt failed with the file named through FM_CONFIG_OVERRIDE"
  [ "$out" = "$expected" ] || fail "the file's text did not land verbatim after an unchanged prompt"$'\n'"--- tail ---"$'\n'"$(printf '%s\n' "$out" | tail -5)"
  out=$(branch_prompt FM_HOME="$home") || fail "branch prompt failed with the file found through FM_HOME"
  [ "$out" = "$expected" ] || fail "FM_HOME/config did not supply the file when no config override was named"
  pass "the file's text is appended verbatim as the last section, after a byte-identical prompt"
}

test_unreadable_path_refuses_the_prompt() {
  local home out rc=0
  home=$(make_home not-a-file)
  mkdir "$home/config/branch-prompt-include.md"
  out=$(branch_prompt FM_HOME="$home" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -ne 0 ] || fail "a directory at the include path still produced a branch prompt"
  assert_contains "$out" "$home/config/branch-prompt-include.md must be a readable regular file" \
    "the refusal did not name the unusable include path"
  pass "an include path that is not a readable regular file refuses the branch prompt"
}

test_absent_or_blank_file_changes_nothing
test_file_text_is_appended_verbatim_as_the_last_section
test_unreadable_path_refuses_the_prompt

echo "# all fm-branch-prompt-include tests passed"
