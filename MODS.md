# 本地定制登记

这个仓库是上游 [kunchenguid/firstmate](https://github.com/kunchenguid/firstmate) 的 fork，本文件登记 fork 里所有不提交给上游的本地定制。
定制按「堂前燕」方式组织：上游文件里只留一行钩子，行尾或行上标 `# GHOST: <说明>`；定制内容放在只属于本 fork 的独立文件里。
拉上游时，冲突只可能落在下面「钩子」和「清单登记」两节列出的几行上。

行号会随上游改动漂移，以 `grep -rn '# GHOST:' bin` 的结果为准；它列出的行应与「钩子」一节逐条对应。

## 钩子

| 上游文件:行 | 做什么 | 定制文件 | 为什么不进上游 |
| --- | --- | --- | --- |
| `bin/fm-spawn.sh:559-560` | 载入 spawn setup 库；559 行是带标记的 `# shellcheck source=` 指令，560 行是 `.` 载入语句 | `bin/ghost/fm-spawn-setup-lib.sh` | 见下文「spawn setup 钩子」 |
| `bin/fm-spawn.sh:3928` | 在 `freshen_spawn_worktree_base` 之后调用 `run_spawn_setup_hook`，给新分到的 worktree 做项目准备 | `bin/ghost/fm-spawn-setup-lib.sh` | 同上 |
| `bin/fm-timeout-lib.sh:23` | 标出头部说明里两段本地句子：`FM_TIMEOUT_MECHANISM_OVERRIDE` 可强制四种机制，以及被信号杀死的命令返回 128 + 信号 | 无，改动留在上游文件里 | 见下文「超时修复」 |
| `bin/fm-timeout-lib.sh:38` | `fm_timeout_mechanism` 的覆盖变量除 `bash` 外也接受 `timeout`、`gtimeout`、`perl`，本机没有该工具时回落到正常探测 | 无，改动留在上游文件里 | 同上 |
| `bin/fm-timeout-lib.sh:153` | perl 兜底机制把被信号杀死的命令报成 128 + 信号，而不是 0 | 无，改动留在上游文件里 | 同上 |
| `bin/fm-branch-prompt.sh:141` | 在监督分支系统提示末尾追加本机 `config/branch-prompt-include.md` 的内容 | `bin/ghost/fm-branch-prompt-include.sh` | 见下文「监督分支提示追加」 |

## 清单登记

`docs/documentation-audiences.json` 里有两条本地登记，JSON 不能写注释，所以标记只记在这里：

- `"path": "MODS.md"`（第 280 行附近），受众 `maintainer-architecture`。
- `"path": "docs/ghost/spawn-setup.md"`（第 368 行附近），受众 `operator-current`。

`tests/fm-documentation-audiences.test.sh` 要求每个被 git 跟踪的 `.md` 文件都在这份清单里，少了这两条测试会失败。

## 只属于本 fork 的文件

这些文件上游没有，拉上游不会冲突：

- `MODS.md` - 本文件。
- `bin/ghost/fm-spawn-setup-lib.sh` - spawn setup 钩子的全部实现，头部注释是它的完整契约。
- `bin/ghost/fm-branch-prompt-include.sh` - 读取并输出 `config/branch-prompt-include.md` 的追加段落。
- `docs/ghost/spawn-setup.md` - spawn setup 钩子的使用说明和两个环境变量。
- `tests/fm-spawn-setup-hook.test.sh` - spawn setup 钩子的行为测试，驱动真实的 `bin/fm-spawn.sh`。
- `tests/fm-timeout-lib.test.sh` - 超时修复的行为测试，四种机制逐一强制运行。
- `tests/fm-branch-prompt-include.test.sh` - 监督分支提示追加的行为测试，覆盖有文件、无文件、空文件和路径不是普通文件四种情况。

## 各项定制

### spawn setup 钩子

firstmate 从 Treehouse 池分给 worker 的 worktree 是裸检出：没装依赖、没有本地 env 文件、没分端口。
这个钩子让本机为每个项目放一个可执行文件 `config/spawn-setup/<项目目录名>`，ship 和 scout 启动前先在 worktree 里跑它。
用法、拒绝条件和重试前要清理的东西见 [`docs/ghost/spawn-setup.md`](docs/ghost/spawn-setup.md)。
不进上游的原因：它服务的是本机池里项目（如 her-web）的准备步骤，本 fork 决定只在本地维护。

### 超时修复

`bin/fm-timeout-lib.sh` 的 `fm_run_timed` 在没有 coreutils 的 macOS 上走 perl 兜底，上游版本把被信号杀死的命令报成退出码 0，调用方会把它当成功。
本地修复让它返回 128 + 信号；spawn setup 钩子靠这个语义拒绝被杀掉的钩子。
这处改动小且散在函数内部，原样留在上游文件里，只加标记，不提交上游。

### 监督分支提示追加

`bin/fm-branch-prompt.sh` 生成 Pi 监督分支的系统提示。
钩子仿照上游 `config/brief-include.md` 的形状：本机 `config/branch-prompt-include.md` 不存在或为空时什么都不加；存在时把内容原样放在提示末尾的 `# Home prompt additions` 段落里，前面所有段落优先于它；路径存在但不是可读的普通文件时拒绝生成提示。
「摘要用简体中文」这条要求写在本机的 `config/branch-prompt-include.md` 里，这个文件不提交。
只读取 `FM_CONFIG_OVERRIDE` 或 `FM_HOME/config` 指定的目录，两者都没设时什么都不加；Pi 扩展每次都显式传这两个变量。
改了配置文件后，要等监督分支下次重建（新开主会话，或切换监督分支的模型或推理强度）才生效。
不进上游的原因：语言偏好只属于本机，上游的提示对所有用户保持逐字节稳定。

## 拉上游之后

1. 解决冲突时保留带 `# GHOST:` 的行；`bin/fm-spawn.sh` 里调用行必须仍紧跟在 `freshen_spawn_worktree_base "$WT" || exit 1` 之后，原因见 `bin/ghost/fm-spawn-setup-lib.sh` 里 `run_spawn_setup_hook` 上方的注释。
2. 运行 `grep -rn '# GHOST:' bin`，核对结果与「钩子」一节一致，行号变了就更新本文件。
3. 运行 `bin/fm-lint.sh`，再运行 `bin/fm-lint.sh bin/ghost/*.sh`：默认的 lint 范围是 `bin/*.sh`、`bin/backends/*.sh` 和 `tests/*.sh`，不包括 `bin/ghost/`。
4. 运行 `bin/fm-test-run.sh tests/fm-spawn-setup-hook.test.sh tests/fm-timeout-lib.test.sh tests/fm-branch-prompt-include.test.sh tests/fm-branch-supervision.test.sh tests/fm-documentation-audiences.test.sh`。
