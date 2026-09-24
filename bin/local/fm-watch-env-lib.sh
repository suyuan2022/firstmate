#!/usr/bin/env bash
# fm-watch-env-lib.sh - home-local watcher timing (config/watch.env).
#
# A local mod, not part of upstream Firstmate: MODS.md registers the two
# fm-watch.sh hook lines (a shellcheck directive and the `.` line) that load
# this file right before the watcher reads its FM_* timing variables.
#
# Why: the watcher's timings (how long before a quiet pane counts as a possible
# wedge, how often a declared wait is rechecked, ...) are environment-only
# upstream. The watcher is started by the Pi extension or the Claude hook, so
# there is no shell to export them from. This file lets a home set them in a
# gitignored file instead.
#
# config/watch.env: optional, home-local, gitignored, not inherited by
# secondmate homes (each home keeps its own). One KEY=VALUE per line; blank
# lines and lines starting with # are ignored. Only the keys in
# FM_LOCAL_WATCH_ENV_KEYS are accepted, and only as positive integers without a
# leading zero. A value already set in the watcher's environment wins. Anything
# else - an unknown key, a bad value, a line without "=" - is skipped with one
# warning on stderr naming the line, and the watcher keeps its default for that
# key; a broken file never stops the watcher.
#
# Scope: only bin/fm-watch.sh reads this file. The away-mode daemon
# (bin/fm-supervise-daemon.sh) also reads FM_PAUSE_RESURFACE_SECS and keeps its
# own environment.
#
# Sourced by bin/fm-watch.sh, never executed. Reads CONFIG.

FM_LOCAL_WATCH_ENV_KEYS="FM_PAUSE_RESURFACE_SECS FM_STALE_ESCALATE_SECS FM_TURNEND_CHURN_ABSORB_SECS FM_BUSY_TURN_MAX_SECS"

fm_local_watch_env_load() {
  local file="$CONFIG/watch.env" line key value lineno=0
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    # Trim surrounding whitespace.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in '' | '#'*) continue ;; esac
    case "$line" in
      *=*) ;;
      *)
        echo "fm-watch: config/watch.env line $lineno: expected KEY=VALUE; ignored" >&2
        continue
        ;;
    esac
    key=${line%%=*}
    value=${line#*=}
    case " $FM_LOCAL_WATCH_ENV_KEYS " in
      *" $key "*) ;;
      *)
        echo "fm-watch: config/watch.env line $lineno: '$key' is not a supported key ($FM_LOCAL_WATCH_ENV_KEYS); ignored" >&2
        continue
        ;;
    esac
    case "$value" in
      '' | *[!0-9]* | 0*)
        echo "fm-watch: config/watch.env line $lineno: $key must be a positive integer without a leading zero; ignored" >&2
        continue
        ;;
    esac
    [ -n "${!key:-}" ] && continue
    export "$key=$value"
  done < "$file"
}

fm_local_watch_env_load
