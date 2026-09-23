# Spawn setup hooks (config/spawn-setup/)

This is a local mod rather than upstream Firstmate behavior; [`MODS.md`](../../MODS.md) registers the two `bin/fm-spawn.sh` hook lines that load and call it.

A worktree from the Treehouse pool is handed to a worker as a bare checkout: no installed dependencies, no local environment file, no allocated ports.
For a project that needs any of that before work can start, put an executable at `config/spawn-setup/<project-directory-basename>` and Firstmate runs it as part of every ship and scout spawn into that project, so the worker's window is already provisioned instead of relying on the worker remembering a setup command.
The optional `config/spawn-setup/` directory is local and gitignored, and it is **not** inherited into secondmate homes: provisioning steps are machine-local, and each home decides for itself whether its pool runs them.
Nothing ships a hook for you, and no repository can carry one: install it yourself in the home whose pool should run it.
An absent hook is a silent no-op, which is every project that has not opted in.

The hook name must match the basename of the project directory Firstmate spawns from, so a clone at `projects/her-web` is provisioned by `config/spawn-setup/her-web`.
Firstmate runs it synchronously, with the current directory set to the task worktree and standard input detached, and waits for it before launching the worker.
The hook receives `FM_TASK_ID`, `FM_TASK_KIND` (`ship` or `scout`), `FM_PROJECT` (the absolute path of the project clone this home spawns from), and `FM_WORKTREE`.
Keep the hook itself a one-line forward to the project's own setup script rather than reimplementing that script's steps, so the two cannot drift apart.
For example, a `config/spawn-setup/her-web` hook forwarding to a shared setup script reads:

```sh
#!/usr/bin/env bash
# Provision a freshly allocated her-web worktree: dependencies, local env file,
# ports. Light tier only - no database container, which `pnpm dev` provisions on
# demand - so a spawn never depends on Docker being up.
set -euo pipefail
export HER_WEB_MAIN_REPO="$FM_PROJECT"
exec bash /path/to/dev-pipeline/scripts/worktree-setup.sh "$PWD" her-web
```

The script's own `HER_WEB_MAIN_REPO` variable is set to `$FM_PROJECT` so it reads the clone Firstmate itself spawns from rather than its built-in default, and the files it copies into the worktree are the ones this home's own checkout carries.

The spawn refuses when the hook exits nonzero, exceeds its time bound, or leaves behind files Git does not ignore.
A hook that is present but is not a runnable file - not executable, a directory, a symlink whose target moved - refuses by name before it is run, because a forgotten `chmod +x` is the likeliest way a configured hook is wrong and a plain exec failure reports it differently on every host.
The dirty-worktree rule is the important one: a hook may write only paths the worktree already ignores, because Firstmate reads any other untracked file as the worker's own unlanded work and would later refuse to clean up that worktree.

A refusal is early enough that no task record, backlog transition, or worker exists, so nothing thinks the task is running.
It is not, however, a full rollback, and retrying the same task id can need up to three things cleared first:

- **Any unignored file the hook wrote**, left in place in the pooled worktree, because Firstmate never deletes untracked work to make a spawn proceed. Until you remove it, the next spawn handed that pool slot refuses too, with `pooled worktree '...' is not clean; refusing to discard uncommitted work while refreshing its base`.
- **The task's window**, created before the hook ran and not killed on refusal. A same-id retry on the tmux backend otherwise stops at `window <session>:fm-<id> already exists`; close the empty window first.
- **The hook log**, kept under the temp directory and named in the refusal, for you to read and then delete.

Hooks are skipped for relaunches, for secondmates, and on the Orca backend, which provisions its worktrees from its own repository hook at creation time.
`FM_SPAWN_SETUP=off` skips a configured hook for one spawn with a notice, for the case where the environment is known good and the seconds are not wanted; any other value refuses rather than guessing.
A hook is bounded at 120 seconds by default, and exceeding the bound refuses the spawn like any other failure.
The default is tight because a hook runs while the spawn still holds the shared Treehouse project lock: for as long as a hook runs, another spawn into the same project, and a teardown returning one of its slots, refuse outright rather than wait ("another Treehouse slot allocation or return is in progress").
`FM_SPAWN_SETUP_TIMEOUT` raises or lowers it in whole seconds; anything that is not a positive integer uses 120.
Raise it when a hook is legitimately slow - a cold package store, a distant registry - rather than reaching for `FM_SPAWN_SETUP=off`, which skips provisioning altogether and is not an escape hatch for slowness.
Anything slower still - a full image build, a database container - belongs in the worker's first command instead of the hook, where it does not hold the lock.
The header of [`bin/ghost/fm-spawn-setup-lib.sh`](../../bin/ghost/fm-spawn-setup-lib.sh) owns the exact mechanics, with regression coverage in [`tests/fm-spawn-setup-hook.test.sh`](../../tests/fm-spawn-setup-hook.test.sh).

## Environment variables

```sh
FM_SPAWN_SETUP=             # optional per-spawn skip of a configured spawn setup hook; only "off" is accepted, any other value refuses
FM_SPAWN_SETUP_TIMEOUT=120  # seconds bounding one spawn setup hook; anything but a positive integer uses 120
```
