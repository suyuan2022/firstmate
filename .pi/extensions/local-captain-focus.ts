// LOCAL: captain focus and routine-note filtering for the Pi primary (MODS.md "船长专注和 ⛵ 备注").
//
// The captain's attention is the bottleneck. Two things pulled it away:
//   - while he hand-tests or discusses a design, every supervision outcome still
//     reached his window and the first mate's next reply;
//   - routine ⛵ notes repeated "still waiting" lines and all of them went into
//     the first mate's model context as custom messages.
//
// fm-branch-supervision.ts has two LOCAL hook lines. As each outcome row is
// read from the store, globalThis.fmLocalDeliverOutcome(row) decides its
// delivery (lib/local-captain-focus-lib.ts `decide`): true means this file
// handled it, false means upstream delivers it unchanged. Before main is handed
// a processing request, globalThis.fmLocalPresentableOutcomes(rows) drops the
// captain rows focus is holding.
//
// Focus is a durable record in state/, switched by the first mate with the
// fm_focus tool (AGENTS.local.md section 9 says when). While it is on, only
// captain rows the supervision branch marked 〔立刻〕 reach main and the captain;
// everything else with something to say goes to the held list, and fm_focus off
// returns it for one reply. Nothing is dropped: held rows stay in the outcome
// store, and a held captain row that later arrives in a processing request is
// acknowledged as usual. If the captain says nothing for FM_FOCUS_IDLE_SECS
// (default 45 minutes), focus ends by itself and the held list goes to the
// first mate in one hidden request, so a forgotten focus cannot hold things
// forever. The away posture (state/.afk-contract) suspends focus; when the
// captain comes back from it, focus ends and what it held goes to the first
// mate in the same run as away mode's own summary, so he hears it all at once.
//
// Routine notes that show are session entries rendered for the captain only,
// never model messages; the first mate reads the store with fm_branch_outcomes.
//
// Gate: the home-local, gitignored presence flag config/captain-focus. Without
// it nothing is installed and upstream behaves exactly as before.
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import {
  decide,
  focusActive,
  formatHeld,
  hold,
  idleExpired,
  paths,
  presentable,
  readFocus,
  readHeld,
  readKeys,
  release,
  returnedFromAway,
  taskStateKey,
  writeFocus,
  writeKey,
  type OutcomeRow,
} from "./lib/local-captain-focus-lib.ts";

const NOTE_ENTRY = "fm-local-routine-note";
const FOCUS_MESSAGE = "fm-local-focus";
const HIDDEN_MARK = "\u2063";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const fmHome = process.env.FM_HOME || process.env.FM_ROOT_OVERRIDE || root;
const stateDir = process.env.FM_STATE_OVERRIDE || join(fmHome, "state");
const configDir = process.env.FM_CONFIG_OVERRIDE || join(fmHome, "config");

type Hooks = {
  fmLocalDeliverOutcome?: (row: OutcomeRow) => boolean;
  fmLocalPresentableOutcomes?: (rows: OutcomeRow[] | null) => OutcomeRow[] | null;
};

function idleSeconds(): number {
  const value = Number(process.env.FM_FOCUS_IDLE_SECS);
  return Number.isSafeInteger(value) && value > 0 ? value : 2700;
}

const now = () => Math.floor(Date.now() / 1000);

function clock(epoch: number): string {
  const d = new Date(epoch * 1000);
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

export default function localCaptainFocus(pi: ExtensionAPI): void {
  if (!existsSync(join(configDir, "captain-focus"))) return;
  const p = paths(stateDir);
  const shown = new Set<number>();
  let timer: ReturnType<typeof setInterval> | undefined;

  (globalThis as Hooks).fmLocalDeliverOutcome = (row) => {
    try {
      returnedFromAway(p); // records that away mode began while focused
      const key = row.task === "fleet" ? "" : taskStateKey(stateDir, row.task);
      const delivery = decide(row, focusActive(p), readKeys(p)[row.task], key);
      if (row.task !== "fleet") writeKey(p, row.task, key);
      switch (delivery) {
        case "upstream":
          return false;
        case "hold":
          hold(p, { kind: "outcome", seq: row.seq, task: row.task, verdict: row.verdict, summary: row.summary, at: now() });
          return true;
        case "show":
          if (!shown.has(row.seq)) {
            shown.add(row.seq);
            pi.appendEntry(NOTE_ENTRY, { seq: row.seq, task: row.task, summary: row.summary });
          }
          return true;
        case "hide":
          return true;
      }
    } catch {
      return false;
    }
  };

  (globalThis as Hooks).fmLocalPresentableOutcomes = (rows) => {
    try {
      // Called at every run boundary before main is handed captain outcomes,
      // including the first one after the captain returns from away mode, so a
      // release here reaches main in the same run as away mode's own summary.
      checkAwayReturn();
      return presentable(p, rows);
    } catch {
      return rows;
    }
  };

  function tellMain(content: string, trigger: boolean): void {
    const message = { customType: FOCUS_MESSAGE, content, display: false };
    if (trigger) pi.sendMessage(message, { triggerTurn: true, deliverAs: "followUp" });
    else pi.sendMessage(message, { triggerTurn: false });
  }

  function focusReminder(): string | undefined {
    const focus = readFocus(p);
    if (!focus.on) return undefined;
    return `（本机专注状态）船长从 ${clock(focus.since)} 起在专注：${focus.topic}。监督消息里不是〔立刻〕的由代码挡着，已攒 ${readHeld(p).length} 件。` +
      "他停下、换话题或问还有什么时，调用 fm_focus off，把返回的内容在一条回复里说完。";
  }

  function checkAwayReturn(): void {
    if (!returnedFromAway(p)) return;
    const focus = readFocus(p);
    const items = release(p, now());
    if (items.length === 0) return;
    const head = "\u8239\u957f\u4ece\u79bb\u5f00\u6a21\u5f0f\u56de\u6765\u4e86";
    tellMain(`${head}，专注（${focus.topic}）随之结束。离开前攒着的事如下，和离开期间的结果放在同一条回复里说完；` +
      "其中带 seq 的如果出现在处理请求里，照常调用 fm_branch_processed，已经说过的只回一句。\n\n" +
      formatHeld(items), true);
  }

  function checkIdle(): void {
    const focus = readFocus(p);
    if (!idleExpired(focus, existsSync(p.afk), now(), idleSeconds())) return;
    const items = release(p, now());
    if (items.length === 0) return;
    tellMain(
      `船长 ${Math.round(idleSeconds() / 60)} 分钟没说话，专注（${focus.topic}）已自动结束。攒着的事如下，整理成一条回复，他回来就能一次看完；` +
        "其中带 seq 的如果之后出现在处理请求里，照常调用 fm_branch_processed，回复只写一句「上面说过了」。\n\n" +
        formatHeld(items),
      true,
    );
  }

  pi.on("session_start", (_event, ctx) => {
    shown.clear();
    for (const entry of ctx.sessionManager.getBranch() as Array<{ type: string; customType?: string; data?: { seq?: unknown } }>) {
      if (entry.type === "custom" && entry.customType === NOTE_ENTRY && typeof entry.data?.seq === "number") shown.add(entry.data.seq);
    }
    if (timer) clearInterval(timer);
    timer = setInterval(() => {
      try {
        checkAwayReturn();
        checkIdle();
      } catch {
        // A later tick retries; focus never blocks supervision.
      }
    }, 60_000);
    timer.unref?.();
    const reminder = focusReminder();
    if (reminder) tellMain(reminder, false);
  });

  pi.on("session_compact", () => {
    const reminder = focusReminder();
    if (reminder) tellMain(reminder, false);
  });

  pi.on("session_shutdown", () => {
    if (timer) clearInterval(timer);
    timer = undefined;
  });

  pi.on("input", (event) => {
    if (event.source !== "interactive" || event.text.startsWith(HIDDEN_MARK)) return { action: "continue" };
    const focus = readFocus(p);
    if (focus.on) writeFocus(p, { ...focus, lastCaptainAt: now() });
    return { action: "continue" };
  });

  pi.registerEntryRenderer?.(NOTE_ENTRY, (entry, _options, theme) => {
    const data = entry.data as { task?: unknown; summary?: unknown } | undefined;
    if (!data || typeof data.task !== "string" || typeof data.summary !== "string") return undefined;
    return new Text(`${theme.fg("customMessageText", "⛵")}${theme.fg("dim", ` ${data.task}: ${data.summary}`)}`, 1, 0);
  });

  pi.registerTool({
    name: "fm_focus",
    label: "Captain focus",
    description:
      "Hold supervision messages while the captain focuses on one thing (hand-testing, a design discussion). " +
      "on: start focus with a short topic. add: hold one item of your own for later. list: show what is held. " +
      "off: end focus and return everything held, to tell the captain in one reply.",
    parameters: Type.Object({
      action: Type.Union([Type.Literal("on"), Type.Literal("off"), Type.Literal("add"), Type.Literal("list")]),
      topic: Type.Optional(Type.String({ description: "For on: what the captain is focused on, a few words" })),
      text: Type.Optional(Type.String({ description: "For add: the item to tell the captain later, one sentence" })),
    }),
    execute: async (_toolCallId, params) => {
      const { action, topic, text } = params as { action: string; topic?: string; text?: string };
      const reply = (message: string, isError = false) => ({
        content: [{ type: "text" as const, text: message }],
        details: undefined,
        ...(isError ? { isError: true } : {}),
      });
      const focus = readFocus(p);
      if (action === "on") {
        const t = now();
        writeFocus(p, { on: true, topic: topic?.trim() || focus.topic || "（未写）", since: focus.on ? focus.since : t, lastCaptainAt: t });
        return reply(`专注已开：${topic?.trim() || focus.topic}。已攒 ${readHeld(p).length} 件。`);
      }
      if (action === "add") {
        if (!text?.trim()) return reply("add 需要 text", true);
        hold(p, { kind: "note", text: text.trim(), at: now() });
        return reply(`记下了，已攒 ${readHeld(p).length} 件。`);
      }
      if (action === "list") {
        return reply(`${focus.on ? `专注中：${focus.topic}` : "现在没在专注"}\n\n${formatHeld(readHeld(p))}`);
      }
      if (action === "off") {
        const items = release(p, now());
        return reply(
          `专注已结束。${formatHeld(items)}` +
            (items.length
              ? "\n\n在这条回复里一次告诉船长。带 seq 的如果之后出现在处理请求里，照常调用 fm_branch_processed，回复只写一句「上面说过了」。"
              : ""),
        );
      }
      return reply(`未知 action：${action}`, true);
    },
  });
}
