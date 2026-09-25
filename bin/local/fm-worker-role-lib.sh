#!/usr/bin/env bash
# fm-worker-role-lib.sh - local addendum to the ship/scout worker role contract.
#
# A local mod, not part of upstream Firstmate: MODS.md registers it ("方案窗").
# bin/fm-dod-lib.sh sources this file and calls fm_local_worker_role_addendum
# right after the sentence in fm_brief_worker_role that tells a worker to
# report only to firstmate and not to address the captain.
#
# Upstream wrote that sentence (702004ed, #3797) so a worker running inside a
# firstmate checkout, which loads AGENTS.md, does not take on the first mate's
# identity and start talking to the captain as if it were the supervisor. This
# home also uses workers as design windows: the captain opens a scout's window
# and discusses the design with it directly, so the first mate does not relay
# every turn. The addendum lets a worker answer the captain in its own window
# and changes nothing else: it still takes no supervisor identity and still
# reports status and results only to firstmate. Firstmate reaches a worker's
# terminal only with the fixed steering-inbox doorbell line (bin/fm-send.sh),
# so any other text typed into the window is the captain.

fm_local_worker_role_addendum() {
  cat <<'EOF'
Exception in this home: text typed into your own window, other than firstmate's steering-inbox doorbell line, is the captain talking to you directly; answer him there in Chinese, and keep reporting status and results only to firstmate as above.
EOF
}
