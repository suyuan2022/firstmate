// LOCAL: collapse slash-command skill bodies in the supervision branch's main-dialog mirror (MODS.md).
//
// When the captain types a skill command such as /afk, /stow, or /bearings in
// the Pi primary, Pi expands the whole skill body into that user message:
//   <skill name="afk" location="...">\n<body>\n</skill>\n\n<what the captain typed>
// fm-branch-supervision.ts mirrors the captain's current message into the
// supervision branch uncapped (upstream #3211), so a 25-35k character skill
// body lands in the branch and is re-read on every later wake. The branch has
// its own away-mode rules and reads state/.afk-contract for the posture, so the
// body is dead weight there (9/19-9/23: 23 such mirrors, about 124k tokens,
// re-read about 17.4M tokens).
//
// fm-branch-supervision.ts's one LOCAL hook line calls
// globalThis.fmLocalMirrorContent(tag, text) when it exists and otherwise
// sends upstream's `[${tag}] ${text}`. This extension installs that function
// when the home-local, gitignored presence flag
// config/branch-mirror-collapse-skills exists in the checkout it lives in.
// The function replaces a captain message that is exactly one Pi skill block
// (optionally followed by the captain's own words) with
// `[captain] ran /<name>` plus those words, and returns upstream's format for
// everything else. The main session's own transcript is untouched.
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// Pi's own skill-block shape (agent-session.js parses it with this pattern).
const SKILL_BLOCK = /^<skill name="([^"]+)" location="([^"]+)">\n([\s\S]*?)\n<\/skill>(?:\n\n([\s\S]+))?$/;

export function collapseMirrorContent(tag: string, text: string): string {
  if (tag === "captain") {
    const match = text.match(SKILL_BLOCK);
    if (match) {
      const words = match[4]?.trim();
      return words ? `[captain] ran /${match[1]}\n\n${words}` : `[captain] ran /${match[1]}`;
    }
  }
  return `[${tag}] ${text}`;
}

export default function localMirrorSkillCollapse(): void {
  const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
  if (!existsSync(join(root, "config", "branch-mirror-collapse-skills"))) return;
  (globalThis as { fmLocalMirrorContent?: (tag: string, text: string) => string }).fmLocalMirrorContent =
    collapseMirrorContent;
}
