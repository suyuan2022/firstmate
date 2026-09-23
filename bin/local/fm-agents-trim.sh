#!/usr/bin/env bash
# fm-agents-trim.sh - generate AGENTS.local.md, the trimmed supervisor contract
# this fork loads instead of the upstream AGENTS.md.
#
# A local mod, not part of upstream Firstmate: MODS.md registers it, together
# with the CLAUDE.md and AGENTS.override.md pointers that load its output.
# Re-run it after every upstream merge, then commit AGENTS.local.md.
#
# It reads AGENTS.md, deletes the whole lines named by the PASSAGES list below,
# and writes AGENTS.local.md with one LOCAL marker line on top. Every passage is
# anchored to one "## " section of AGENTS.md and must match inside it exactly
# once: a single line by its leading text, a range by its first and last lines
# plus a pinned line count, or a whole section. When any passage is missing,
# ambiguous, or has changed length, the script names every such passage, writes
# nothing, and exits 1, so an upstream rewrite gets re-reviewed here instead of
# being silently kept or silently over-deleted.
#
# Usage:
#   fm-agents-trim.sh [--source <AGENTS.md>] [--output <AGENTS.local.md>]
#   fm-agents-trim.sh --check [--source <AGENTS.md>] [--output <AGENTS.local.md>]
#
# --check writes nothing. It exits 0 when the output file already holds exactly
# what a run would generate, and exits 1 naming the fix when it does not. Both
# paths default to AGENTS.md and AGENTS.local.md at this repository's root.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 - "$ROOT" "$@" <<'PY'
import difflib
import os
import sys
import tempfile

HEADER = (
    "<!-- LOCAL: generated from AGENTS.md by bin/local/fm-agents-trim.sh; "
    "do not edit by hand, re-run the script after every upstream merge (MODS.md). -->\n"
)

# (group, section heading prefix, kind, anchor)
#   line:    anchor is the line's leading text
#   range:   anchor is (first line's leading text, last line's leading text, line count)
#   section: anchor is None; the heading line through the line before the next heading
PASSAGES = [
    # (a) Relay
    ("a", "## 14.", "section", None),
    ("a", "## 8.", "line", "Relay may require that same live cycle with no fleet work."),
    ("a", "## 8.", "line", "When Relay-linked work reaches a milestone or terminal state"),
    ("a", "## 13.", "line", "- `fmx-respond` - "),
    ("a", "## 2.", "line", "config/x-mode.env "),
    ("a", "## 2.", "line", "  x-watch.check.sh "),
    ("a", "## 2.", "line", "  x-inbox/ "),
    ("a", "## 2.", "line", "  x-context/ "),
    ("a", "## 2.", "line", "  x-outbox/ "),
    ("a", "## 2.", "line", "  public-followup/ "),
    ("a", "## 2.", "line", "  x-poll.error "),
    # (b) Unused backends and tools
    ("b", "## 2.", "line", "  <id>.grok-turnend-token "),
    ("b", "## 2.", "line", "  <id>.kimi-turnend-token "),
    ("b", "## 2.", "line", "  <id>.gemini-settings.json "),
    ("b", "## 2.", "line", "  <id>.muse-session "),
    ("b", "## 2.", "line", "  <id>.cursor-session "),
    ("b", "## 2.", "line", "  .cursor-park-owner "),
    ("b", "## 2.", "line", "config/cmux-socket-password "),
    ("b", "## 2.", "line", "  mail.check.sh "),
    ("b", "## 2.", "line", "  .mail-seen "),
    ("b", "## 13.", "line", "- `firstmate-orca` - "),
    ("b", "## 13.", "line", "- `firstmate-codexapp` - "),
    # (c) Dispatch candidate arrays
    ("c", "## 4.", "range", ("Firstmate alone resolves a matched profile array", "Load `quota-array-dispatch` ", 10)),
    ("c", "## 13.", "line", "- `quota-array-dispatch` - "),
]

USAGE = (
    "usage: fm-agents-trim.sh [--check] [--source <AGENTS.md>] [--output <AGENTS.local.md>]\n"
)


def die(message, code=1):
    sys.stderr.write(f"fm-agents-trim: {message}\n")
    sys.exit(code)


root = sys.argv[1]
args = sys.argv[2:]
check = False
source = os.path.join(root, "AGENTS.md")
output = os.path.join(root, "AGENTS.local.md")
while args:
    arg = args.pop(0)
    if arg == "--check":
        check = True
    elif arg in ("--source", "--output"):
        if not args:
            die(f"{arg} requires a path\n{USAGE}", 2)
        if arg == "--source":
            source = args.pop(0)
        else:
            output = args.pop(0)
    elif arg in ("-h", "--help"):
        sys.stdout.write(USAGE)
        sys.exit(0)
    else:
        die(f"unknown argument: {arg}\n{USAGE}", 2)

try:
    with open(source, encoding="utf-8") as handle:
        lines = handle.read().splitlines(keepends=True)
except OSError as error:
    die(f"cannot read {source}: {error}")

# Section spans by "## " heading, ignoring headings inside fenced code blocks.
headings = []
fenced = False
for index, line in enumerate(lines):
    if line.startswith("```"):
        fenced = not fenced
    elif not fenced and line.startswith("## "):
        headings.append(index)


def section_span(prefix):
    found = [i for i in headings if lines[i].startswith(prefix + " ")]
    if len(found) != 1:
        return None, f"section '{prefix}' found {len(found)} times (expected exactly once)"
    start = found[0]
    later = [i for i in headings if i > start]
    return (start, later[0] if later else len(lines)), None


def matches(span, anchor):
    return [i for i in range(span[0], span[1]) if lines[i].startswith(anchor)]


doomed = set()
errors = []
for group, prefix, kind, anchor in PASSAGES:
    span, error = section_span(prefix)
    label = f"({group}) {kind} in '{prefix}'"
    if error:
        errors.append(f"{label}: {error}")
        continue
    if kind == "section":
        chosen = set(range(span[0], span[1]))
    elif kind == "line":
        hits = matches(span, anchor)
        if len(hits) != 1:
            errors.append(f"{label} starting '{anchor}': found {len(hits)} times (expected exactly once)")
            continue
        chosen = {hits[0]}
    else:
        first, last, count = anchor
        starts, ends = matches(span, first), matches(span, last)
        if len(starts) != 1 or len(ends) != 1:
            errors.append(
                f"{label} from '{first}' to '{last}': first line found {len(starts)} times, "
                f"last line found {len(ends)} times (expected exactly once each)"
            )
            continue
        if ends[0] - starts[0] + 1 != count:
            errors.append(
                f"{label} from '{first}' to '{last}': spans {ends[0] - starts[0] + 1} lines (expected {count})"
            )
            continue
        chosen = set(range(starts[0], ends[0] + 1))
    if chosen & doomed:
        errors.append(f"{label}: overlaps an earlier passage")
        continue
    doomed |= chosen

if errors:
    sys.stderr.write(
        f"fm-agents-trim: {len(errors)} passage(s) no longer match {source}; "
        "re-review them against the new upstream text and update PASSAGES; nothing was written\n"
    )
    for error in errors:
        sys.stderr.write(f"  - {error}\n")
    sys.exit(1)

generated = HEADER + "".join(line for i, line in enumerate(lines) if i not in doomed)

if check:
    try:
        with open(output, encoding="utf-8") as handle:
            current = handle.read()
    except FileNotFoundError:
        die(f"{output} is missing; run bin/local/fm-agents-trim.sh")
    if current != generated:
        diff = list(
            difflib.unified_diff(
                current.splitlines(keepends=True),
                generated.splitlines(keepends=True),
                output,
                "generated",
            )
        )
        sys.stderr.write(
            f"fm-agents-trim: {output} does not match what {source} generates; "
            "run bin/local/fm-agents-trim.sh and commit the result\n"
        )
        sys.stderr.write("".join(diff[:40]))
        sys.exit(1)
    print(f"fm-agents-trim: {output} is current")
    sys.exit(0)

directory = os.path.dirname(os.path.abspath(output))
fd, temporary = tempfile.mkstemp(dir=directory, prefix=".fm-agents-trim.")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(generated)
    os.chmod(temporary, 0o644)
    os.replace(temporary, output)
except BaseException:
    if os.path.exists(temporary):
        os.unlink(temporary)
    raise
print(f"fm-agents-trim: wrote {output} ({len(doomed)} lines removed in {len(PASSAGES)} passages)")
PY
