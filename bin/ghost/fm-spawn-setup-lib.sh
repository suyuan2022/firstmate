#!/usr/bin/env bash
# fm-spawn-setup-lib.sh - the single owner of home-local spawn setup hooks.
#
# A local mod, not part of upstream Firstmate: MODS.md registers the two
# fm-spawn.sh hook lines that load this library and call it, and
# docs/ghost/spawn-setup.md is its operator guide.
#
# Sourced by bin/fm-spawn.sh, never executed. run_spawn_setup_hook reads the
# spawn's CONFIG, PROJ_ABS, ID, KIND, and BACKEND globals at call time and
# bounds the hook with fm_run_timed, which fm-spawn.sh sources from
# bin/fm-timeout-lib.sh before this file.
#
# Spawn setup hook (config/spawn-setup/<project-dir-basename>):
#   Optional per-project provisioning for the worktree a ship or scout spawn is
#   about to launch into, so a worker never opens on a bare pool checkout with
#   no dependencies, local env file, or allocated ports. An absent hook is a
#   silent no-op, which is every project that has not opted in. A hook that is
#   present but not a runnable file refuses by name rather than by exec failure,
#   whose diagnostic varies with the host's timeout mechanism.
#   It runs synchronously with cwd set to the task worktree and stdin detached,
#   under a hard FM_SPAWN_SETUP_TIMEOUT bound (default 120 seconds; invalid or
#   zero values use 120), receiving FM_TASK_ID, FM_TASK_KIND, FM_PROJECT (the
#   absolute project clone this home spawns from), and FM_WORKTREE. It runs
#   while this spawn still holds the shared Treehouse project lock, so another
#   spawn or a teardown for the same project refuses rather than waits for as
#   long as a hook runs; the bound caps that window, which is why the default is
#   tight and a hook that legitimately needs longer raises it rather than
#   skipping provisioning.
#   A nonzero exit, the bound, or a worktree left carrying files git does not
#   ignore refuses the spawn and names the kept hook log; a hook may write only
#   ignored paths, because anything else is later read as the worker's own
#   unlanded work. No task record, backlog transition, or worker is created, but
#   a refusal can leave the already-created task window, the kept log, and any
#   unignored path the hook wrote in the pooled worktree;
#   docs/ghost/spawn-setup.md lists what to clear before retrying the same task
#   id.
#   Skipped for relaunches, secondmates, and the orca backend, which provisions
#   its worktrees from its own repository hook. FM_SPAWN_SETUP=off skips a
#   configured hook for one spawn with a notice; any other value refuses.
#   The directory is home-local and gitignored, and is NOT inherited into
#   secondmate homes (bin/fm-config-inherit-lib.sh).

# Per-project provisioning for the worktree this spawn is about to launch into.
#
# A pool slot is handed over as a bare checkout: no installed dependencies, no
# local env file, no allocated ports. Firstmate cannot know what any project
# needs, so the hook IS the whole contract - an executable at
# config/spawn-setup/<project-dir-basename>, run with cwd set to the task
# worktree. An absent hook means the project needs nothing, which is every
# project that has not opted in. The knowledge lives in the home's own
# gitignored config/ rather than in the project, because the steps are
# machine-local and a borrowed repository cannot know which pool borrowed it.
#
# Placement carries the safety, so keep the fm-spawn.sh call where it is. It
# runs after freshen_spawn_worktree_base, so that clean-tree refusal still
# inspects a tree no hook has touched, and before fm-spawn.sh writes the
# worktree's .claude/settings.local.json, so a hook that syncs a main
# checkout's .claude/ cannot overwrite firstmate's own busy and turn-end wiring.
# Both are before any per-task state exists, which puts a refusal here in the
# same class as freshen's: the abort trap releases the slot claim, and no task
# record, backlog transition, or worker is ever created.
#
# "No task state" is not "nothing on disk", and the difference is what an
# operator has to clear before retrying the same id. A refusal here can leave
# the task window this spawn already created (spawn_abort_cleanup releases locks
# and the slot claim but kills no window outside the orca backend), the kept
# hook log under the temp directory, and - for the dirty-tree refusal below -
# whatever unignored path the hook wrote, which freshen_spawn_worktree_base then
# refuses that pooled slot over until a human clears it.
# docs/ghost/spawn-setup.md lists all three for the operator.
#
# A hook may write only paths the worktree already ignores. That is asserted
# rather than trusted, because bin/fm-teardown.sh reads any other untracked file
# as the worker's own unlanded work and would then refuse to return the slot.
# Refusing here instead means the operator meets the problem while the hook's
# output is still the newest thing on disk.
run_spawn_setup_hook() { # <worktree>
  local worktree=$1 hook log status rc=0 bound=${FM_SPAWN_SETUP_TIMEOUT:-120}
  # Orca provisions its own worktrees from its own repository hook at creation
  # time, so it is the one backend that arrives here already set up; running a
  # second hook over it would only duplicate that work. A relaunch and a
  # secondmate never reach this call: fm-spawn.sh skips them for the same reason
  # they skip the base refresh, since neither acquires a worktree there.
  [ "$BACKEND" != orca ] || return 0
  case "$bound" in '' | *[!0-9]* | 0*) bound=120 ;; esac
  hook="$CONFIG/spawn-setup/$(basename "$PROJ_ABS")"
  # Absent is the unconfigured majority and stays silent. Every other shape
  # reports, because a hook the captain wrote and firstmate then skipped is the
  # exact failure this hook exists to remove.
  if [ ! -e "$hook" ] && [ ! -L "$hook" ]; then
    return 0
  fi
  case "${FM_SPAWN_SETUP:-}" in
  '') ;;
  off)
    echo "notice: FM_SPAWN_SETUP=off; skipping $hook, so this worker starts in an unprovisioned worktree" >&2
    return 0
    ;;
  *)
    echo "error: FM_SPAWN_SETUP is '$FM_SPAWN_SETUP'; the only accepted value is off (unset or empty runs the project's spawn-setup hook)" >&2
    return 1
    ;;
  esac
  # A forgotten chmod +x is the likeliest way a configured hook is wrong, and
  # exec failure alone does not name it: fm_run_timed's mechanism is whichever
  # of timeout/gtimeout/perl/bash the host has, and on a stock macOS host - no
  # coreutils, so the perl fallback - a failed exec in the forked child prints
  # nothing and exits 255. Naming the shape here keeps that diagnostic the same
  # on every host instead of depending on which timeout binary is installed.
  if [ ! -f "$hook" ] || [ ! -x "$hook" ]; then
    echo "error: spawn-setup hook '$hook' is not a runnable file; it must be a regular file with the executable bit set (chmod +x it, repoint it if its symlink target moved, or remove it); refusing to launch a worker into an unprovisioned worktree" >&2
    return 1
  fi
  log=$(mktemp "${TMPDIR:-/tmp}/fm-spawn-setup.XXXXXX" 2>/dev/null) || {
    echo "error: could not create a log file for spawn-setup hook '$hook'; refusing to launch a worker whose provisioning could not be recorded" >&2
    return 1
  }
  # stdin is detached and the bound is hard (bin/fm-timeout-lib.sh kills the
  # whole process group), so a hook that prompts or wedges cannot hold the spawn
  # open while it still owns the shared Treehouse project lock.
  (
    cd "$worktree" || exit 1
    export FM_TASK_ID="$ID" FM_TASK_KIND="$KIND" FM_PROJECT="$PROJ_ABS" FM_WORKTREE="$worktree"
    fm_run_timed "$bound" "$hook"
  ) >"$log" 2>&1 </dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ "$rc" -eq 124 ]; then
      echo "error: spawn-setup hook '$hook' did not finish within ${bound}s in '$worktree'; refusing to launch a worker into a half-provisioned worktree" >&2
    else
      echo "error: spawn-setup hook '$hook' failed (exit $rc) in '$worktree'; refusing to launch a worker into an unprovisioned worktree" >&2
    fi
    spawn_setup_hook_leftovers "$worktree"
    spawn_setup_hook_log_tail "$log"
    return 1
  fi
  status=$(git -C "$worktree" -c core.quotePath=false status --porcelain) || {
    echo "error: could not inspect '$worktree' after spawn-setup hook '$hook' ran; refusing to launch" >&2
    spawn_setup_hook_log_tail "$log"
    return 1
  }
  if [ -n "$status" ]; then
    echo "error: spawn-setup hook '$hook' left files git does not ignore in '$worktree'; a hook may write only ignored paths, because anything else is later read as the worker's own unlanded work; refusing to launch" >&2
    spawn_setup_hook_leftovers "$worktree" "$status"
    spawn_setup_hook_log_tail "$log"
    return 1
  fi
  rm -f "$log" 2>/dev/null || true
}

# Every refusal names the unignored paths the hook left in the pooled worktree,
# because clearing them is the first thing a retry of the same task id needs:
# freshen_spawn_worktree_base refuses that slot until they are gone. A hook
# interrupted partway through is the likeliest to have written one, so this
# belongs to the failure and timeout refusals as much as to the dirty-tree one.
# Silent when the tree is clean, or unreadable and some other refusal is already
# being reported. A caller that already read the porcelain text passes it in, so
# one observation backs both its verdict and this excerpt: re-reading after the
# bound has signalled the hook's process group can catch a grandchild still
# flushing and print an excerpt that contradicts the refusal above it.
spawn_setup_hook_leftovers() { # <worktree> [<porcelain-status>]
  local worktree=$1 status
  if [ "$#" -ge 2 ]; then
    status=$2
  else
    status=$(git -C "$worktree" -c core.quotePath=false status --porcelain 2>/dev/null) || return 0
  fi
  [ -n "$status" ] || return 0
  echo "--- first 10 entries of git status in $worktree ---" >&2
  printf '%s\n' "$status" | head -10 >&2
}

# The tail is the actionable part of a failed hook: the error the project's own
# setup script printed. The complete log is kept and named, so a truncated
# excerpt is never the only copy of what went wrong.
spawn_setup_hook_log_tail() { # <log>
  local log=$1
  if [ -s "$log" ]; then
    echo "--- last 10 lines of $log ---" >&2
    tail -n 10 "$log" >&2 || true
    echo "--- end of excerpt; complete output kept at $log ---" >&2
  else
    echo "the hook produced no output; its empty log is kept at $log" >&2
  fi
}
