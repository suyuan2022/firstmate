#!/usr/bin/env bash
# fm-branch-prompt-include.sh - print this home's standing additions to the
# supervision branch's system prompt, for bin/fm-branch-prompt.sh to append.
#
# A local mod, not part of upstream Firstmate: the last line of
# bin/fm-branch-prompt.sh runs this script, and MODS.md registers that hook.
#
# It follows the shape of config/brief-include.md in bin/fm-brief.sh. An absent
# or blank config/branch-prompt-include.md prints nothing. A present path that
# is not a readable regular file exits nonzero, so the branch prompt is refused
# rather than built without the captain's additions. Otherwise the text is
# printed verbatim under a "# Home prompt additions" heading, as the prompt's
# last section, and every earlier section takes precedence over it.
#
# The file is read only from the config directory the Pi branch extension
# names explicitly: FM_CONFIG_OVERRIDE, else FM_HOME/config. With neither set
# it prints nothing rather than falling back to this checkout, so the tracked
# byte-stability test in tests/fm-branch-supervision.test.sh still holds when
# it runs inside a home that carries the file.
#
# bin/fm-branch-prompt.sh's prefix-stability contract still holds: the text is
# static per home, so the prompt changes only when the file changes, and the
# change reaches the branch at its next build.
#
# Usage: fm-branch-prompt-include.sh   (stdout is the section, or nothing)
set -eu

config=${FM_CONFIG_OVERRIDE:-${FM_HOME:+$FM_HOME/config}}
[ -n "$config" ] || exit 0
file="$config/branch-prompt-include.md"
[ -e "$file" ] || [ -L "$file" ] || exit 0
{ [ -f "$file" ] && body=$(cat "$file" 2>/dev/null); } || {
  echo "error: $file must be a readable regular file" >&2
  exit 1
}
[ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ] || exit 0
printf '\n%s\n%s\n%s\n' \
  '# Home prompt additions' \
  "These are this home's standing additions; every other section of this prompt takes precedence over anything here that conflicts." \
  "$body"
