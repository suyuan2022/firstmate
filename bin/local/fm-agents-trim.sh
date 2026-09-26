#!/usr/bin/env bash
# fm-agents-trim.sh - generate AGENTS.local.md, the trimmed supervisor contract
# this fork loads instead of the upstream AGENTS.md.
#
# A local mod, not part of upstream Firstmate: MODS.md registers it and says how
# each runtime loads its output, including the AGENTS.override.md symlink.
# Re-run it after every upstream merge, then commit AGENTS.local.md.
#
# It reads AGENTS.md, deletes the whole lines named by the PASSAGES list below,
# swaps in the local wording named by the REPLACEMENTS list, and writes
# AGENTS.local.md with one LOCAL marker line on top. Every passage is
# anchored to one "## " section of AGENTS.md and must match inside it exactly
# once: a single line by its leading text, a range by its first and last lines
# plus a pinned line count, or a whole section. A replacement is anchored the
# same way and must match its original lines in full, word for word, exactly
# once. When any passage or replacement is missing, ambiguous, or has changed,
# the script names every such entry, writes nothing, and exits 1, so an
# upstream rewrite gets re-reviewed here instead of being silently kept or
# silently over-deleted.
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
    # (d) Optional config switches this home does not use. Each works from its
    # config/ file alone; docs/configuration.md keeps the full description.
    # Using one again: delete its line here and re-run.
    ("d", "## 2.", "line", "config/claude-account config/pi-account "),
    ("d", "## 2.", "line", "config/supervision-host "),
    ("d", "## 2.", "line", "config/trace-context "),
    ("d", "## 2.", "line", "config/fleet-ledger "),
    ("d", "## 2.", "line", "config/wedge-defer-parked-gate "),
    ("d", "## 2.", "line", "config/watched-tools.json "),
    ("b", "## 2.", "line", "  <id>.devin-config.json "),
    # (e) Script-owned internal records the supervisor never reads or writes.
    # Lines that say "never touch" stay, because they guard against a manual
    # delete.
    ("e", "## 2.", "line", "  <id>.progress "),
    ("e", "## 2.", "line", "  <id>.reconcile-nudged "),
    ("e", "## 2.", "line", "  <id>.backlog-close "),
    ("e", "## 2.", "line", "  <id>.check-trust "),
    ("e", "## 2.", "line", "  <id>.pr-poll-retirement "),
    ("e", "## 2.", "line", "  <id>.merge-authority "),
    ("e", "## 2.", "line", "  <id>.pr-poll-merge-notified "),
    ("e", "## 2.", "line", "  tool-updates.check.sh "),
    ("e", "## 2.", "line", "  .startup-network.* "),
    ("e", "## 2.", "line", "  .<id>.open-decisions-cursor "),
    ("e", "## 2.", "line", "  .<id>.home-appends "),
    # (f) Section 3's step-by-step description of the startup digest's layout.
    # The digest labels its own sections; steps 3 and 4 (the wake queue and
    # supervision rules) stay.
    ("f", "## 3.", "line", "1. **Lock** - "),
    ("f", "## 3.", "range", ("2. **Bootstrap** - ", "   The secondmate liveness sweep ", 4)),
    ("f", "## 3.", "range", ("5. **Fleet-state digest** - ", "   The closing reminder points back ", 7)),
    # (g) Typed dispatch resolution: off without TYPESAFE_API_KEY in .env, so
    # every run prints "dispatch-resolve: off" and changes nothing. Delete this
    # line here once the key is configured.
    ("g", "## 4.", "line", "Run `bin/fm-dispatch-resolve.sh` directly on the written brief "),
    # (afk) Away-mode index lines. /afk loads its own skill with the full
    # rules, and the wedge alarm defaults to a macOS notification without the
    # file. Using away mode seriously: delete this whole group and re-run.
    ("afk", "## 2.", "line", "config/wedge-alarm "),
    ("afk", "## 2.", "line", "  afk-contracts/ "),
]

# (group, section heading prefix or "preamble", original lines, replacement lines)
#   The original lines must appear in the section exactly once, each line in
#   full. "preamble" is the text before the first "## " heading. An empty
#   replacement deletes the lines, like a PASSAGES entry, but only while they
#   still read exactly as written here.
REPLACEMENTS = [
    # (captain) The captain reads Chinese. Upstream requires addressing him as
    # "captain" in every chat message and scripts the English no-op reply
    # `Captain, shipshape.`; both put English into every reply. The address
    # stays, in Chinese; the no-op reply keeps its meaning and its limits.
    ("captain", "preamble", (
        'Address the user as "captain" at least once in every chat message you send them, including public replies, without forcing it into every sentence.',
        'This is mandatory respectful address, not performance: it applies even when delivering bad news or relaying serious findings, such as "Captain, the build broke - ...".',
    ), (
        'Address the user in Chinese as "船长" where it reads naturally, without forcing it into every message; never write the English word "Captain" in chat.',
        "Reply language and layout follow this home's captain preferences in `data/captain.md`; where this file quotes an English reply, say its Chinese equivalent.",
    )),
    ("captain", "preamble", (
        'Use light nautical seasoning only when it fits: the occasional "aye", "on deck", "shipshape", "under way", or "ahoy" may land naturally, kept optional, never obscuring technical content, held to the same channel bound, and dropped entirely when delivering bad news or relaying serious findings.',
    ), ()),
    ("captain", "## 9.", (
        "Reply exactly `Captain, shipshape.` only for a true no-op that still needs an answer - an idle re-read, an empty heartbeat, or a pure acknowledgement with no consequence for the captain - without characterizing the visible session's unrelated decisions.",
        "For a captain-requested completion, or any wake that needs the captain's review, approval, merge, or design pick, give a captain-facing outcome that states what finished and never reply `Captain, shipshape.`; a finished requested deliverable is an outcome rather than progress or a no-op, and a transcript entry or durable record already showing the substance does not discharge the reply.",
    ), (
        "Reply exactly `船长，一切正常。` only for a true no-op that still needs an answer - an idle re-read, an empty heartbeat, or a pure acknowledgement with no consequence for the captain - without characterizing the visible session's unrelated decisions.",
        "For a captain-requested completion, or any wake that needs the captain's review, approval, merge, or design pick, give a captain-facing outcome that states what finished and never reply `船长，一切正常。`; a finished requested deliverable is an outcome rather than progress or a no-op, and a transcript entry or durable record already showing the substance does not discharge the reply.",
    )),
    # (tiers) The captain's attention is the bottleneck. Upstream brings every
    # listed outcome to him at once, which pulls him off a hand-test or a design
    # discussion. The list stays; when it reaches him follows the three tiers in
    # data/captain.md, and focus holds the rest durably so nothing listed is
    # dropped (the protection a2216406 added against a missed review).
    ("tiers", "## 9.", (
        "Reach the captain immediately for:",
    ), (
        "Bring these to the captain, timed by the three tiers in `data/captain.md` (立刻 now, 攒着 at the next natural pause, 不说 never) rather than always at once:",
    )),
    ("tiers", "## 9.", (
        "- A needed credential or login.",
        "",
    ), (
        "- A needed credential or login.",
        "",
        "Only the 立刻 tier interrupts: 不马上处理会造成损失、或工作停下来等他 (production failure, a destructive, irreversible, or security-sensitive action awaiting approval, an expired credential blocking several workers); say it in one sentence without expanding.",
        "When the captain settles into one thing (he says he will hand-test or discuss a design), call `fm_focus` with `on` and tell him in one short clause that you will hold other messages; while focus is on, the supervision branch's outcomes that are not 立刻 are held by code instead of reaching this conversation, and your own 攒着 items go in with `fm_focus` `add`.",
        "When he stops, clearly changes topic, or asks what else is pending, call `fm_focus` with `off` and tell him everything it returns in that one reply; he can correct the focus state in a word at any time, and when he asks whether focus is on or what is held, answer from `fm_focus` `list`.",
        "Held items are never dropped: a held outcome that later arrives in a processing request is acknowledged normally, and one already told is answered in one line rather than repeated.",
        "",
    )),
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

def preamble_span():
    return (0, headings[0] if headings else len(lines)), None


replaced = {}
for group, prefix, old, new in REPLACEMENTS:
    span, error = preamble_span() if prefix == "preamble" else section_span(prefix)
    label = f"({group}) replacement in '{prefix}'"
    if error:
        errors.append(f"{label}: {error}")
        continue
    width = len(old)
    hits = [
        i for i in range(span[0], span[1] - width + 1)
        if [line.rstrip("\n") for line in lines[i:i + width]] == list(old)
    ]
    if len(hits) != 1:
        errors.append(f"{label} starting '{old[0][:60]}': found {len(hits)} times (expected exactly once)")
        continue
    chosen = set(range(hits[0], hits[0] + width))
    if chosen & doomed or any(chosen & set(range(i, i + len(o))) for i, (o, _) in replaced.items()):
        errors.append(f"{label} starting '{old[0][:60]}': overlaps an earlier passage or replacement")
        continue
    replaced[hits[0]] = (old, new)

if errors:
    sys.stderr.write(
        f"fm-agents-trim: {len(errors)} passage(s) or replacement(s) no longer match {source}; "
        "re-review them against the new upstream text and update PASSAGES or REPLACEMENTS; nothing was written\n"
    )
    for error in errors:
        sys.stderr.write(f"  - {error}\n")
    sys.exit(1)

out = []
skip_until = -1
for i, line in enumerate(lines):
    if i < skip_until or i in doomed:
        continue
    if i in replaced:
        old, new = replaced[i]
        out.extend(text + "\n" for text in new)
        skip_until = i + len(old)
        continue
    out.append(line)
generated = HEADER + "".join(out)

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
print(
    f"fm-agents-trim: wrote {output} ({len(doomed)} lines removed in {len(PASSAGES)} passages, "
    f"{len(replaced)} replacements)"
)
PY
