// LOCAL: pure logic for .pi/extensions/local-captain-focus.ts (MODS.md "船长专注和 ⛵ 备注").
//
// No Pi imports, so tests/local/fm-captain-focus.test.sh can load it with plain
// node. Every file it touches lives under the home's state/ directory and is
// written atomically (temp file plus rename); an unreadable file reads as empty
// so a broken record never stops supervision - the hook then falls back to
// upstream delivery, which shows the outcome.
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

// Summary prefixes the supervision branch writes (config/branch-prompt-include.md
// tells it when). The outcome store only allows `silent` on fleet rows, so the
// branch marks a task note with nothing new, and a captain outcome the captain
// must hear at once, in the summary text instead.
export const NO_NEWS = "〔无新进展〕";
export const URGENT = "〔立刻〕";

export type OutcomeRow = { seq: number; task: string; verdict: "routine" | "captain"; summary: string; silent: boolean };

export type HeldItem =
  | { kind: "outcome"; seq: number; task: string; verdict: "routine" | "captain"; summary: string; at: number }
  | { kind: "note"; text: string; at: number };

// awaySeen: the away posture was active at some point while focus was on.
// tasks: tasks the first mate named when turning focus on.
// sends: how many of the first mate's commands during this focus steered each
// task (fm-send.sh or fm-lease.sh claim); see focusTasks.
export type FocusRecord = {
  on: boolean;
  topic: string;
  since: number;
  lastCaptainAt: number;
  awaySeen?: boolean;
  tasks?: string[];
  sends?: Record<string, number>;
};

export type Paths = { focus: string; held: string; history: string; keys: string; afk: string; state: string };

export function paths(state: string): Paths {
  return {
    state,
    focus: join(state, ".local-focus.json"),
    held: join(state, ".local-focus-held.jsonl"),
    history: join(state, ".local-focus-history.jsonl"),
    keys: join(state, ".local-note-keys.json"),
    afk: join(state, ".afk-contract"),
  };
}

function readJson<T>(file: string, fallback: T): T {
  try {
    return JSON.parse(readFileSync(file, "utf8")) as T;
  } catch {
    return fallback;
  }
}

function writeAtomic(file: string, text: string): void {
  mkdirSync(dirname(file), { recursive: true });
  const temporary = `${file}.${process.pid}.tmp`;
  writeFileSync(temporary, text);
  renameSync(temporary, file);
}

export function readFocus(p: Paths): FocusRecord {
  const record = readJson<Partial<FocusRecord>>(p.focus, {});
  return {
    on: record.on === true,
    topic: typeof record.topic === "string" ? record.topic : "",
    since: typeof record.since === "number" ? record.since : 0,
    lastCaptainAt: typeof record.lastCaptainAt === "number" ? record.lastCaptainAt : 0,
    awaySeen: record.awaySeen === true,
    tasks: Array.isArray(record.tasks) ? record.tasks.filter((task): task is string => typeof task === "string") : [],
    sends: record.sends && typeof record.sends === "object" ? record.sends : {},
  };
}

/**
 * The tasks the captain is working through right now. The first mate steers
 * the task under test on every step (claim, then send), so a task steered at
 * least twice during this focus counts; one steer can be a stray follow-up in
 * the same breath as turning focus on. Tasks named at `on` always count.
 */
export function focusTasks(focus: FocusRecord): string[] {
  const steered = Object.entries(focus.sends ?? {}).filter(([, count]) => count >= 2).map(([task]) => task);
  return [...new Set([...(focus.tasks ?? []), ...steered])].sort();
}

/** Task ids a shell command steers through fm-send.sh or claims through fm-lease.sh. */
export function tasksFromCommand(command: string): string[] {
  const found = new Set<string>();
  const pattern = /fm-(?:send\.sh|lease\.sh\s+claim)\s+([A-Za-z0-9][A-Za-z0-9._-]*)/g;
  for (const match of command.matchAll(pattern)) found.add(match[1]);
  return [...found];
}

/** Counts one steering command during focus; outside focus it records nothing. */
export function noteSteer(p: Paths, tasks: string[]): void {
  if (tasks.length === 0) return;
  const focus = readFocus(p);
  if (!focus.on) return;
  const sends = { ...(focus.sends ?? {}) };
  for (const task of tasks) sends[task] = (sends[task] ?? 0) + 1;
  writeFocus(p, { ...focus, sends });
}

export function writeFocus(p: Paths, record: FocusRecord): void {
  writeAtomic(p.focus, `${JSON.stringify(record)}\n`);
}

/** Focus holds only while the away posture is absent: /afk has its own, stronger rules. */
export function focusActive(p: Paths): boolean {
  return readFocus(p).on && !existsSync(p.afk);
}

export function readHeld(p: Paths): HeldItem[] {
  let text = "";
  try {
    text = readFileSync(p.held, "utf8");
  } catch {
    return [];
  }
  const items: HeldItem[] = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    try {
      items.push(JSON.parse(line) as HeldItem);
    } catch {
      // A torn line from a crash is skipped; the outcome itself is still in the store.
    }
  }
  return items;
}

export function hold(p: Paths, item: HeldItem): void {
  const items = readHeld(p);
  if (item.kind === "outcome" && items.some((held) => held.kind === "outcome" && held.seq === item.seq)) return;
  items.push(item);
  writeAtomic(p.held, items.map((held) => JSON.stringify(held)).join("\n") + "\n");
}

/** Ends focus and hands back everything held; the held list moves to the history file. */
export function release(p: Paths, now: number): HeldItem[] {
  const focus = readFocus(p);
  const items = readHeld(p);
  if (items.length > 0) {
    const history = (() => {
      try {
        return readFileSync(p.history, "utf8");
      } catch {
        return "";
      }
    })();
    const entry = JSON.stringify({ releasedAt: now, topic: focus.topic, items });
    writeAtomic(p.history, `${history}${entry}\n`);
  }
  writeAtomic(p.held, "");
  writeFocus(p, { ...focus, on: false, awaySeen: false, tasks: [], sends: {} });
  return items;
}

/**
 * Tracks the away posture across focus. Returns true exactly when the captain
 * has come back from away mode while focus was on: focus should then end, so
 * what was held before he left and what away mode gathered reach him together.
 */
export function returnedFromAway(p: Paths): boolean {
  const focus = readFocus(p);
  if (!focus.on) return false;
  if (existsSync(p.afk)) {
    if (!focus.awaySeen) writeFocus(p, { ...focus, awaySeen: true });
    return false;
  }
  return focus.awaySeen === true;
}

/** Focus the captain has left alone this long ends by itself (never while away). */
export function idleExpired(focus: FocusRecord, away: boolean, nowSec: number, idleSec: number): boolean {
  return focus.on && !away && nowSec - Math.max(focus.lastCaptainAt, focus.since) >= idleSec;
}

/** Captain outcomes to present to main while focused: held ones wait for release. */
export function presentable(p: Paths, rows: OutcomeRow[] | null): OutcomeRow[] | null {
  if (rows === null || !focusActive(p)) return rows;
  const held = new Set(readHeld(p).flatMap((item) => (item.kind === "outcome" ? [item.seq] : [])));
  return rows.filter((row) => !held.has(row.seq));
}

/**
 * The task state a routine note is compared against: the kind of the latest
 * status line (working, paused, done, needs-decision, ...) plus the recorded PR.
 * A change here always shows the note.
 */
export function taskStateKey(state: string, task: string): string {
  let kind = "";
  try {
    const lines = readFileSync(join(state, `${task}.status`), "utf8").split("\n").filter((line) => line.trim());
    const last = lines[lines.length - 1] ?? "";
    kind = (last.match(/^([a-z][a-z-]*)/) ?? ["", ""])[1];
  } catch {
    kind = "";
  }
  let pr = "";
  try {
    const meta = readFileSync(join(state, `${task}.meta`), "utf8");
    pr = (meta.match(/^pr=(.*)$/m) ?? ["", ""])[1].trim();
  } catch {
    pr = "";
  }
  return `${kind}|${pr}`;
}

export type Delivery = "upstream" | "hold" | "show" | "hide";

/**
 * What happens to one outcome row as the supervision extension reads it:
 *   upstream - a captain row outside focus, or a 立刻 row: upstream's visible entry and processing request;
 *   hold     - focus is on and the row has something to say: kept in the held list for release;
 *   show     - a routine note with news: shown to the captain only, never to main's model;
 *   hide     - a routine note with nothing new (its task state unchanged and the
 *              branch marked it, or a silent fleet heartbeat): left in the store only.
 * When unsure it shows.
 */
export function decide(row: OutcomeRow, focused: boolean, previousKey: string | undefined, key: string): Delivery {
  if (row.verdict === "captain") {
    if (!focused || row.summary.startsWith(URGENT)) return "upstream";
    return "hold";
  }
  if (row.task === "fleet" && row.silent) return "hide";
  const stateChanged = row.task === "fleet" || previousKey === undefined || previousKey !== key;
  if (!stateChanged && row.summary.startsWith(NO_NEWS)) return "hide";
  return focused ? "hold" : "show";
}

export function readKeys(p: Paths): Record<string, string> {
  return readJson<Record<string, string>>(p.keys, {});
}

export function writeKey(p: Paths, task: string, key: string): void {
  const keys = readKeys(p);
  if (keys[task] === key) return;
  keys[task] = key;
  writeAtomic(p.keys, `${JSON.stringify(keys)}\n`);
}

function describe(item: HeldItem): string {
  if (item.kind === "note") return `- ${item.text}`;
  const label = item.verdict === "captain" ? `[seq ${item.seq}] ` : "";
  return `- ${label}${item.task}: ${item.summary}`;
}

/**
 * The held list for the first mate, with the tasks under test first: he steered
 * those step by step and has usually told the captain already, so he only adds
 * what was not said.
 */
export function formatHeldForRelease(items: HeldItem[], tasks: string[]): string {
  const underTest = new Set(tasks);
  const mine = items.filter((item) => item.kind === "outcome" && underTest.has(item.task));
  const rest = items.filter((item) => !(item.kind === "outcome" && underTest.has(item.task)));
  if (mine.length === 0) return formatHeld(rest);
  const head = "\u6b63\u5728\u6d4b\u7684\u4efb\u52a1";
  const parts = [head + "（" + [...underTest].join("、") + "）的结果（" + mine.length + " 条，手测时多半已当面说过，只补没说过的）：\n" + mine.map(describe).join("\n")];
  if (rest.length) parts.push(formatHeld(rest));
  return parts.join("\n\n");
}

export function formatHeld(items: HeldItem[]): string {
  if (items.length === 0) return "没有攒着的事。";
  const captain = items.filter((item) => item.kind === "note" || item.verdict === "captain");
  const routine = items.filter((item) => item.kind === "outcome" && item.verdict === "routine");
  const parts: string[] = [];
  if (captain.length) parts.push(`要船长看或拍板的（${captain.length} 件）：\n${captain.map(describe).join("\n")}`);
  if (routine.length) parts.push(`期间的进展备注（${routine.length} 条，挑有用的说）：\n${routine.map(describe).join("\n")}`);
  return parts.join("\n\n");
}
