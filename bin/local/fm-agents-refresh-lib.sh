#!/usr/bin/env bash
# fm-agents-refresh-lib.sh - make the Pi post-compaction instruction refresh in
# bin/fm-session-start.sh check and reprint the contract Pi actually loads.
#
# A local mod, not part of upstream Firstmate: MODS.md registers the two
# fm-session-start.sh hook lines (a shellcheck directive and the `.` line)
# that load this file right after the AGENTS_START_HASH block.
#
# Why: upstream's refresh (e8c76458, #2163) hashes and prints $FM_ROOT/AGENTS.md.
# This fork's Pi reads AGENTS.override.md, a symlink to the trimmed
# AGENTS.local.md (MODS.md "Trimmed AGENTS"). Without this file a drifted
# compaction would print the full upstream contract and tell Pi it supersedes
# the trimmed one, undoing the trim for the rest of the session; and a change
# to the trim list alone would never count as drift.
#
# What: when $FM_ROOT/AGENTS.override.md exists, the start-of-session hash, the
# drift check, and the reprint all use it; otherwise they use AGENTS.md exactly
# as upstream does. The two functions below replace upstream's definitions of
# the same names with bodies that differ only in the file they read and the
# wording naming it. tests/local/fm-agents-refresh.test.sh pins fingerprints of
# the upstream bodies, so an upstream change to either function fails that test
# until this file is re-checked against it.
#
# Sourced by bin/fm-session-start.sh, never executed. Reads FM_ROOT,
# AGENTS_BASELINE_FILE, and AGENTS_START_HASH, and calls hash_file_sha256,
# agents_refresh_required, and section from fm-session-start.sh.

# The instruction file this home's Pi loads.
fm_local_agents_contract() {
  if [ -f "$FM_ROOT/AGENTS.override.md" ]; then
    printf '%s\n' "$FM_ROOT/AGENTS.override.md"
  else
    printf '%s\n' "$FM_ROOT/AGENTS.md"
  fi
}

# Replaces fm-session-start.sh's agents_baseline_drifted: same rules, but the
# current hash is the loaded contract's.
agents_baseline_drifted() {  # <rebuilding-session-pid>
  local lock_pid=$1 baseline_pid baseline_hash current_hash
  [ -f "$AGENTS_BASELINE_FILE" ] && [ ! -L "$AGENTS_BASELINE_FILE" ] || return 0
  baseline_pid=$(sed -n '1p' "$AGENTS_BASELINE_FILE" 2>/dev/null || true)
  baseline_hash=$(sed -n '2p' "$AGENTS_BASELINE_FILE" 2>/dev/null || true)
  current_hash=$(hash_file_sha256 "$(fm_local_agents_contract)" 2>/dev/null || true)
  [ -n "$current_hash" ] || return 0
  [ "$baseline_pid" = "$lock_pid" ] && [ "$baseline_hash" = "$current_hash" ] && return 1
  return 0
}

# Replaces fm-session-start.sh's print_agents_refresh_if_required: same gate
# and section heading, but prints the loaded contract and names it.
print_agents_refresh_if_required() {  # <rebuilding-session-pid>
  local lock_pid=$1 contract name
  agents_refresh_required "$lock_pid" || return 0
  section "CURRENT AGENTS.md - INSTRUCTION REFRESH"
  contract=$(fm_local_agents_contract)
  name=${contract##*/}
  if [ -f "$contract" ]; then
    if [ "$name" = AGENTS.md ]; then
      cat <<'EOF'
The complete on-disk AGENTS.md below supersedes the instruction copy this session
started with. Apply it as the current Firstmate instruction contract.

EOF
    else
      cat <<'EOF'
The complete on-disk AGENTS.override.md below (this home's trimmed AGENTS.local.md,
the file this session loads instead of AGENTS.md) supersedes the instruction copy
this session started with. Apply it as the current Firstmate instruction contract.

EOF
    fi
    cat "$contract"
  else
    printf 'The original %s baseline no longer matches, but the current file is absent.\n' "$name"
  fi
}

# The true start's baseline must hash the same file the drift check reads, or
# every compaction would count as drift.
if [ -n "${AGENTS_START_HASH:-}" ]; then
  AGENTS_START_HASH=$(hash_file_sha256 "$(fm_local_agents_contract)" 2>/dev/null || true)
fi
