#!/usr/bin/env bash
# tests/local/fm-captain-focus.test.sh - captain focus and routine-note filtering
# (.pi/extensions/local-captain-focus.ts, its pure logic in
# .pi/extensions/lib/local-captain-focus-lib.ts, and two LOCAL hook lines in
# .pi/extensions/fm-branch-supervision.ts; a local mod registered in MODS.md).
#
# The pure logic runs with plain node against scratch state directories. The
# extension itself is loaded the way Pi loads it (import, call the default
# export with an API object) from a scratch checkout with stubbed Pi packages,
# with and without the home flag, and driven through the two hook functions it
# installs and its fm_focus tool. The hook lines are asserted to call those
# functions and to fall back to upstream delivery, so an upstream edit that
# drops or reshapes a line fails here.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

command -v node >/dev/null 2>&1 || { echo "# skip: node not installed"; exit 0; }

TMP_ROOT=$(fm_test_tmproot fm-captain-focus)
LIB="$ROOT/.pi/extensions/lib/local-captain-focus-lib.ts"
EXT="$ROOT/.pi/extensions/local-captain-focus.ts"
BRANCH_EXT="$ROOT/.pi/extensions/fm-branch-supervision.ts"

# Runs a JavaScript file as an ES module; prints its output.
run_js() { # <file> [args...]
  node --no-warnings "$@"
}

test_delivery_decisions() {
  local js="$TMP_ROOT/decide.mjs" out
  cat > "$js" <<JS
import { decide, NO_NEWS, URGENT } from "file://$LIB";
const r = (task, verdict, summary, silent = false) => ({ seq: 1, task, verdict, summary, silent });
const cases = [
  ["captain outside focus", decide(r("t", "captain", "PR 可审"), false, "a", "a"), "upstream"],
  ["captain in focus", decide(r("t", "captain", "PR 可审"), true, "a", "a"), "hold"],
  ["urgent captain in focus", decide(r("t", "captain", URGENT + "正式站挂了"), true, "a", "a"), "upstream"],
  ["first note for a task", decide(r("t", "routine", NO_NEWS + "仍在等"), false, undefined, "paused|"), "show"],
  ["state changed", decide(r("t", "routine", NO_NEWS + "仍在等"), false, "working|", "paused|"), "show"],
  ["unchanged, marked no news", decide(r("t", "routine", NO_NEWS + "仍在等"), false, "paused|", "paused|"), "hide"],
  ["unchanged, not marked", decide(r("t", "routine", "测试站部署完了"), false, "paused|", "paused|"), "show"],
  ["unchanged, marked, in focus", decide(r("t", "routine", NO_NEWS + "仍在等"), true, "paused|", "paused|"), "hide"],
  ["news in focus", decide(r("t", "routine", "测试站部署完了"), true, "paused|", "paused|"), "hold"],
  ["silent fleet heartbeat", decide(r("fleet", "routine", "无变化", true), false, undefined, ""), "hide"],
  ["fleet action", decide(r("fleet", "routine", "清理了一个工作树"), false, undefined, ""), "show"],
];
for (const [label, got, want] of cases) console.log(got === want ? "ok" : \`bad \${label}: got \${got}, want \${want}\`);
JS
  out=$(run_js "$js") || fail "the decision script failed"
  if printf '%s\n' "$out" | grep -q '^bad'; then fail "$(printf '%s\n' "$out" | grep '^bad')"; fi
  pass "captain rows hold in focus unless urgent; routine notes show on a state change or unmarked news and hide only when unchanged and marked"
}

test_hold_release_and_presentable() {
  local state="$TMP_ROOT/state-hold" js="$TMP_ROOT/hold.mjs" out
  mkdir -p "$state"
  printf 'working: 开始\npaused [at=1]: waiting for captain hand-test - A6 就绪\n' > "$state/t1.status"
  printf 'kind=ship\npr=https://example.test/pr/9\n' > "$state/t1.meta"
  cat > "$js" <<JS
import { existsSync, writeFileSync } from "node:fs";
import { formatHeld, hold, idleExpired, paths, presentable, readFocus, readHeld, release, taskStateKey, writeFocus } from "file://$LIB";
const p = paths("$state");
const check = (label, ok) => console.log(ok ? "ok" : \`bad \${label}\`);
check("state key", taskStateKey("$state", "t1") === "paused|https://example.test/pr/9");
check("missing task", taskStateKey("$state", "nope") === "|");
writeFocus(p, { on: true, topic: "手测", since: 100, lastCaptainAt: 100 });
hold(p, { kind: "outcome", seq: 7, task: "t1", verdict: "captain", summary: "PR 可审", at: 1 });
hold(p, { kind: "outcome", seq: 7, task: "t1", verdict: "captain", summary: "PR 可审", at: 1 });
hold(p, { kind: "note", text: "问 Toby 那件事", at: 2 });
check("hold dedupes by seq", readHeld(p).length === 2);
const rows = [7, 8].map((seq) => ({ seq, task: "t1", verdict: "captain", summary: "x", silent: false }));
check("held row kept from main", JSON.stringify(presentable(p, rows).map((r) => r.seq)) === "[8]");
check("unreadable store stays unreadable", presentable(p, null) === null);
writeFileSync(p.afk, "away\n");
check("away posture suspends focus", presentable(p, rows).length === 2);
check("no idle end while away", !idleExpired(readFocus(p), true, 100000, 60));
check("idle end after the limit", idleExpired(readFocus(p), false, 160, 60));
check("no idle end before it", !idleExpired(readFocus(p), false, 159, 60));
const items = release(p, 200);
check("release returns everything", items.length === 2 && readHeld(p).length === 0 && !readFocus(p).on);
check("release keeps a history", existsSync(p.history));
check("released rows reach main again", presentable(p, rows).length === 2);
check("format names both kinds", formatHeld(items).includes("[seq 7] t1: PR 可审") && formatHeld(items).includes("问 Toby 那件事"));
JS
  out=$(run_js "$js") || fail "the hold script failed"
  if printf '%s\n' "$out" | grep -q '^bad'; then fail "$(printf '%s\n' "$out" | grep '^bad')"; fi
  pass "held items survive in state, stay away from main while focused, come back on release, and away mode suspends focus"
}

make_checkout() { # <name> <flag:yes|no>
  local d="$TMP_ROOT/checkout-$1"
  mkdir -p "$d/.pi/extensions/lib" "$d/config" "$d/state" \
    "$d/node_modules/@earendil-works/pi-tui" "$d/node_modules/typebox" "$d/node_modules/@earendil-works/pi-coding-agent"
  cp "$EXT" "$d/.pi/extensions/local-captain-focus.ts"
  cp "$LIB" "$d/.pi/extensions/lib/local-captain-focus-lib.ts"
  printf '{"name":"@earendil-works/pi-tui","type":"module","exports":"./index.js"}\n' > "$d/node_modules/@earendil-works/pi-tui/package.json"
  printf 'export class Text { constructor(text) { this.text = text; } }\nexport class Container {}\n' > "$d/node_modules/@earendil-works/pi-tui/index.js"
  printf '{"name":"typebox","type":"module","exports":"./index.js"}\n' > "$d/node_modules/typebox/package.json"
  printf 'const id = (...a) => a; export const Type = { Object: id, Union: id, Literal: id, Optional: id, String: id };\n' > "$d/node_modules/typebox/index.js"
  printf '{"name":"@earendil-works/pi-coding-agent","type":"module","exports":"./index.js"}\n' > "$d/node_modules/@earendil-works/pi-coding-agent/package.json"
  printf 'export {};\n' > "$d/node_modules/@earendil-works/pi-coding-agent/index.js"
  [ "$2" = yes ] && : > "$d/config/captain-focus"
  printf '%s\n' "$d"
}

test_extension_end_to_end() {
  local d js="$TMP_ROOT/ext.mjs" out
  d=$(make_checkout on yes)
  printf 'paused [at=1]: waiting for captain hand-test\n' > "$d/state/t1.status"
  cat > "$js" <<JS
const d = process.argv[2];
const entries = [], messages = [], handlers = {}, tools = {};
const eventHandlers = {};
const pi = {
  on: (name, fn) => { (handlers[name] ??= []).push(fn); },
  appendEntry: (type, data) => entries.push({ type, data }),
  sendMessage: (message, options) => messages.push({ message, options }),
  registerTool: (tool) => { tools[tool.name] = tool; },
  registerEntryRenderer: () => {},
  events: { on: (name, fn) => { (eventHandlers[name] ??= []).push(fn); } },
};
const m = await import(\`file://\${d}/.pi/extensions/local-captain-focus.ts\`);
m.default(pi);
const deliver = globalThis.fmLocalDeliverOutcome, presentable = globalThis.fmLocalPresentableOutcomes;
const check = (label, ok) => console.log(ok ? "ok" : \`bad \${label}\`);
const row = (seq, task, verdict, summary) => ({ seq, task, verdict, summary, silent: false });
check("hooks installed", typeof deliver === "function" && typeof presentable === "function");
check("captain row goes upstream outside focus", deliver(row(1, "t1", "captain", "PR 可审")) === false);
check("routine note after it with no news is hidden", deliver(row(2, "t1", "routine", "〔无新进展〕仍在等")) === true && entries.length === 0);
check("routine news is shown as an entry, not a message", deliver(row(3, "t1", "routine", "测试站部署完了")) === true && entries.length === 1 && messages.length === 0);
check("same seq is not shown twice", deliver(row(3, "t1", "routine", "测试站部署完了")) === true && entries.length === 1);
await tools.fm_focus.execute("c1", { action: "on", topic: "手测发送前" });
for (const fn of handlers.input) fn({ text: "好了", source: "interactive" });
check("urgent captain row still goes upstream", deliver(row(4, "t1", "captain", "〔立刻〕正式站挂了")) === false);
check("ordinary captain row is held", deliver(row(5, "t1", "captain", "PR 可审")) === true);
check("routine news is held, not shown", deliver(row(6, "t1", "routine", "PR 开好了")) === true && entries.length === 1);
const rows = [4, 5].map((seq) => row(seq, "t1", "captain", "x"));
check("held captain row kept from main", JSON.stringify(presentable(rows).map((r) => r.seq)) === "[4]");
await tools.fm_focus.execute("c2", { action: "add", text: "问 Toby 那件事" });
const listed = await tools.fm_focus.execute("c3", { action: "list" });
check("list shows focus and items", listed.content[0].text.includes("手测发送前") && listed.content[0].text.includes("问 Toby"));
const off = await tools.fm_focus.execute("c4", { action: "off" });
const text = off.content[0].text;
check("off returns every held item", text.includes("[seq 5]") && text.includes("PR 开好了") && text.includes("问 Toby"));
check("after off main gets the held row again", presentable(rows).length === 2);
check("after off routine news shows again", deliver(row(7, "t1", "routine", "工人开始改了")) === true && entries.length === 2);
check("broken input never blocks upstream", deliver(null) === false);

// The tool never shows in the captain's window; a session export still shows it.
const tool = tools.fm_focus;
const theme = { fg: (_c, s) => s, bold: (s) => s };
const result = { content: [{ type: "text", text: "x" }] };
check("tool draws its own row", tool.renderShell === "self");
check("call row is empty", tool.renderCall({}, theme, {}).constructor.name === "Container");
check("result row is empty", tool.renderResult(result, {}, theme, {}).constructor.name === "Container");
for (const fn of eventHandlers["firstmate:calm-presentation"] ?? []) fn({ active: true, stockExportRendering: true });
check("export shows the call", tool.renderCall({}, theme, {}).text === "fm_focus");
check("export shows the result", tool.renderResult(result, {}, theme, {}).text === "x");
for (const fn of eventHandlers["firstmate:calm-presentation"] ?? []) fn({ active: true, stockExportRendering: false });
check("back to empty after export", tool.renderResult(result, {}, theme, {}).constructor.name === "Container");

// Results carry no counts.
const onText = (await tool.execute("c7", { action: "on", topic: "t" })).content[0].text;
const addText = (await tool.execute("c8", { action: "add", text: "y" })).content[0].text;
check("on and add carry no count", !/\d/.test(onText) && !/\d/.test(addText));
await tool.execute("c9", { action: "off" });

// Away mode while focused: focus pauses, then ends on return and hands
// everything to main in one triggered request.
const { writeFileSync, rmSync } = await import("node:fs");
await tools.fm_focus.execute("c5", { action: "on", topic: "聊方案" });
check("held before leaving", deliver(row(8, "t1", "captain", "调研做完了")) === true);
writeFileSync(\`\${d}/state/.afk-contract\`, "away\n");
check("away mode passes captain rows to upstream", deliver(row(9, "t1", "captain", "PR 可审")) === false);
check("nothing released while away", presentable([row(8, "t1", "captain", "x")]).length === 1 && messages.length === 0);
rmSync(\`\${d}/state/.afk-contract\`);
const back = presentable([row(8, "t1", "captain", "x")]);
check("return ends focus and main gets the held row", back.length === 1);
const told = messages.at(-1);
check("return hands the held list to main in one triggered request",
  messages.length === 1 && told.options.triggerTurn === true && told.message.display === false && told.message.content.includes("[seq 8]"));
const listedAfter = await tools.fm_focus.execute("c6", { action: "list" });
check("focus is off after the return", listedAfter.content[0].text.startsWith("现在没在专注"));
JS
  out=$(run_js "$js" "$d") || fail "the extension script failed"$'\n'"$out"
  if printf '%s\n' "$out" | grep -q '^bad'; then fail "$(printf '%s\n' "$out" | grep '^bad')"; fi

  d=$(make_checkout off no)
  out=$(node --no-warnings --input-type=module -e "
delete globalThis.fmLocalDeliverOutcome;
const m = await import('file://$d/.pi/extensions/local-captain-focus.ts');
m.default({ on() {}, registerTool() {}, registerEntryRenderer() {} });
console.log(typeof globalThis.fmLocalDeliverOutcome);
") || fail "the extension failed to load without its flag"
  [ "$out" = undefined ] || fail "the extension installed its hooks without config/captain-focus"
  pass "the extension holds, shows, hides, and releases through its hooks and tool, and installs nothing without its flag"
}

test_hook_lines_call_the_local_functions() {
  local deliver present
  deliver=$(grep -c 'fmLocalDeliverOutcome?.(row) === true) { /\* delivered, held, or hidden locally \*/ } else if (row.verdict === "captain") { // LOCAL:' "$BRANCH_EXT")
  present=$(grep -c 'fmLocalPresentableOutcomes?.(read) ?? read)(await readUnprocessedOutcomes(expectedGeneration)); // LOCAL:' "$BRANCH_EXT")
  [ "$deliver" -eq 1 ] || fail "the delivery hook line is missing or changed in fm-branch-supervision.ts"
  [ "$present" -eq 1 ] || fail "the presentation hook line is missing or changed in fm-branch-supervision.ts"
  pass "fm-branch-supervision.ts carries both hook lines, each falling back to upstream when no local function is installed"
}

test_delivery_decisions
test_hold_release_and_presentable
test_extension_end_to_end
test_hook_lines_call_the_local_functions

echo "# all fm-captain-focus tests passed"
