# 本地定制登记

这个仓库是上游 [kunchenguid/firstmate](https://github.com/kunchenguid/firstmate) 的 fork，本文件登记 fork 里所有不提交给上游的本地定制。
定制按「堂前燕」方式组织：上游文件里只留一行钩子，shell 里在行尾或行上标 `# LOCAL: <说明>`，Markdown 里标 `<!-- LOCAL: <说明> -->`；定制内容放在只属于本 fork 的独立文件里（`bin/local/`、`docs/local/`、`tests/local/`）。
拉上游时，冲突只可能落在下面「钩子」和「清单登记」两节列出的几行上。

行号会随上游改动漂移，以 `grep -rnE '# LOCAL:|<!-- LOCAL:' bin CLAUDE.md` 的结果为准；它列出的行应与「钩子」一节逐条对应。

**每次合入上游之后，都要重新运行 `bin/local/fm-agents-trim.sh` 并提交生成的 `AGENTS.local.md`**，完整步骤见文末「拉上游之后」。

## 钩子

| 上游文件:行 | 做什么 | 定制文件 | 为什么不进上游 |
| --- | --- | --- | --- |
| `bin/fm-spawn.sh:559-560` | 载入 spawn setup 库；559 行是带标记的 `# shellcheck source=` 指令，560 行是 `.` 载入语句 | `bin/local/fm-spawn-setup-lib.sh` | 见下文「spawn setup 钩子」 |
| `bin/fm-spawn.sh:3928` | 在 `freshen_spawn_worktree_base` 之后调用 `run_spawn_setup_hook`，给新分到的 worktree 做项目准备 | `bin/local/fm-spawn-setup-lib.sh` | 同上 |
| `bin/fm-timeout-lib.sh:23` | 标出头部说明里两段本地句子：`FM_TIMEOUT_MECHANISM_OVERRIDE` 可强制四种机制，以及被信号杀死的命令返回 128 + 信号 | 无，改动留在上游文件里 | 见下文「超时修复」 |
| `bin/fm-timeout-lib.sh:38` | `fm_timeout_mechanism` 的覆盖变量除 `bash` 外也接受 `timeout`、`gtimeout`、`perl`，本机没有该工具时回落到正常探测 | 无，改动留在上游文件里 | 同上 |
| `bin/fm-timeout-lib.sh:153` | perl 兜底机制把被信号杀死的命令报成 128 + 信号，而不是 0 | 无，改动留在上游文件里 | 同上 |
| `bin/fm-branch-prompt.sh:141` | 在监督分支系统提示末尾追加本机 `config/branch-prompt-include.md` 的内容 | `bin/local/fm-branch-prompt-include.sh` | 见下文「监督分支提示追加」 |
| `CLAUDE.md:1-2` | 第 1 行是标记，第 2 行把 Claude 的导入从 `@AGENTS.md` 改成 `@AGENTS.local.md` | `AGENTS.local.md` | 见下文「精简版 AGENTS」 |

## 清单登记

`docs/documentation-audiences.json` 里有四条本地登记，JSON 不能写注释，所以标记只记在这里：

- `"path": "AGENTS.local.md"` 和 `"path": "AGENTS.override.md"`（第 268、272 行附近），受众 `agent-runtime`。
- `"path": "MODS.md"`（第 288 行附近），受众 `maintainer-architecture`。
- `"path": "docs/local/spawn-setup.md"`（第 376 行附近），受众 `operator-current`。

`tests/fm-documentation-audiences.test.sh` 要求每个被 git 跟踪的 `.md` 文件（包括符号链接）都在这份清单里，少了这些条目测试会失败。

## 只属于本 fork 的文件

这些文件上游没有，拉上游不会冲突：

- `MODS.md` - 本文件。
- `AGENTS.local.md` - 精简版监督契约，由 `bin/local/fm-agents-trim.sh` 生成，第 1 行是 `<!-- LOCAL: -->` 标记，不手改。
- `AGENTS.override.md` - 指向 `AGENTS.local.md` 的符号链接，给 Codex 和 Pi 读。
- `bin/local/fm-spawn-setup-lib.sh` - spawn setup 钩子的全部实现，头部注释是它的完整契约。
- `bin/local/fm-branch-prompt-include.sh` - 读取并输出 `config/branch-prompt-include.md` 的追加段落。
- `bin/local/fm-agents-trim.sh` - 从 `AGENTS.md` 生成 `AGENTS.local.md`，要删的段落清单写在脚本的 `PASSAGES` 里。
- `docs/local/spawn-setup.md` - spawn setup 钩子的使用说明和两个环境变量。
- `tests/fm-local-mods.test.sh` - 测试入口 `bin/fm-test-run.sh` 只发现 `tests/*.test.sh`，这个文件依次运行 `tests/local/` 下的全部测试，让它们进入 `--all`、CI 分片和覆盖检查。
- `tests/local/fm-spawn-setup-hook.test.sh` - spawn setup 钩子的行为测试，驱动真实的 `bin/fm-spawn.sh`。
- `tests/local/fm-timeout-lib.test.sh` - 超时修复的行为测试，四种机制逐一强制运行。
- `tests/local/fm-branch-prompt-include.test.sh` - 监督分支提示追加的行为测试，覆盖有文件、无文件、空文件和路径不是普通文件四种情况。
- `tests/local/fm-agents-trim.test.sh` - 精简脚本的行为测试：段落全部找到、缺段落时报错、`--check` 发现过期，并检查仓库里提交的 `AGENTS.local.md` 与当前 `AGENTS.md` 一致。

## 各项定制

### spawn setup 钩子

firstmate 从 Treehouse（本机的 worktree 池）分给 worker 的 worktree 是裸检出：没装依赖、没有本地 env 文件、没分端口。
这个钩子让本机为每个项目放一个可执行文件 `config/spawn-setup/<项目目录名>`，ship（交付改动的任务）和 scout（只出调查报告的任务）的 worker 启动前，先在 worktree 里跑它。
用法、拒绝条件和重试前要清理的东西见 [`docs/local/spawn-setup.md`](docs/local/spawn-setup.md)。
不进上游的原因：它服务的是本机池里项目（如 her-web）的准备步骤，本 fork 决定只在本地维护。

### 超时修复

`bin/fm-timeout-lib.sh` 的 `fm_run_timed` 在没有 coreutils 的 macOS 上走 perl 兜底，上游版本把被信号杀死的命令报成退出码 0，调用方会把它当成功。
本地修复让它返回 128 + 信号；spawn setup 钩子靠这个语义拒绝被杀掉的钩子。
这处改动小且散在函数内部，原样留在上游文件里，只加标记，不提交上游。

### 监督分支提示追加

`bin/fm-branch-prompt.sh` 生成 Pi 监督分支的系统提示；监督分支是 firstmate 在 Pi 运行时里专门处理 worker 事件的第二个对话，它写的结果摘要会转给主对话。
钩子仿照上游 `config/brief-include.md` 的形状：本机 `config/branch-prompt-include.md` 不存在或为空时什么都不加；存在时把内容原样放在提示末尾的 `# Home prompt additions` 段落里，前面所有段落优先于它；路径存在但不是可读的普通文件时拒绝生成提示。
「摘要用简体中文」这条要求写在本机的 `config/branch-prompt-include.md` 里，这个文件不提交。
只读取 `FM_CONFIG_OVERRIDE` 或 `FM_HOME/config` 指定的目录，两者都没设时什么都不加；Pi 扩展每次都显式传这两个变量。
改了配置文件后，要等监督分支下次重建（新开主会话，或切换监督分支的模型或推理强度）才生效。
不进上游的原因：语言偏好只属于本机，上游的提示对所有用户保持逐字节稳定。

### 精简版 AGENTS

上游 `AGENTS.md` 是每个 firstmate 会话都要全文加载的监督契约，其中有本机用不到的内容。
`bin/local/fm-agents-trim.sh` 读上游 `AGENTS.md`，按整行删掉三组内容，生成 `AGENTS.local.md`：

- (a) Relay（公开提及集成）：第 14 节全部、第 8 节里两句只讲 Relay 的句子、第 13 节的 `fmx-respond` 条目、第 2 节目录清单里 7 行 Relay 生成文件。
- (b) 本机不用的运行时和工具：第 2 节里 grok、kimi、gemini、muse、cursor 的任务状态文件行，`.cursor-park-owner`、`config/cmux-socket-password`、`mail.check.sh` 和 `.mail-*` 各行；第 13 节的 `firstmate-orca`、`firstmate-codexapp` 条目。
- (c) 调度候选数组：第 4 节从「Firstmate alone resolves a matched profile array」到「Load `quota-array-dispatch` ...」的 10 行，以及第 13 节的 `quota-array-dispatch` 条目。

no-mistakes 相关内容一律保留。
逐条清单的唯一出处是脚本里的 `PASSAGES`；每条都锚定在所属章节里，必须恰好匹配一次，区间还固定了行数。
上游改动让任何一条找不到、匹配多处或行数变了，脚本就列出全部问题、什么都不写、以非零退出，这时对照新的上游文本更新 `PASSAGES` 再重跑。
`bin/local/fm-agents-trim.sh --check` 只检查 `AGENTS.local.md` 是否与当前 `AGENTS.md` 生成的结果一致，不写文件。

各运行时这样加载精简版：

- Claude Code 读 `CLAUDE.md`，它导入 `@AGENTS.local.md`。
- Codex 和 Pi 在同一目录下优先读 `AGENTS.override.md`，读到的就是 `AGENTS.local.md` 的全文；它们原样读取、不展开 `@` 导入，所以这里用符号链接而不是一行指针。
- 其他运行时（opencode 等）仍读完整的 `AGENTS.md`。

两个本机相关的注意点：

- 本机全局 gitignore（`~/.config/git/ignore`）有 `*.local.md` 规则，`AGENTS.local.md` 是用 `git add -f` 纳入跟踪的；已跟踪的文件不受忽略规则影响，重新生成后照常 `git add` 即可。
- `bin/fm-ensure-agents-md.sh` 在本仓库会报 conflict，因为 `CLAUDE.md` 不再是标准的 `@AGENTS.md` 指针；这是预期结果，不要照它的提示把 `CLAUDE.md` 改回去。

不进上游的原因：删掉哪些内容取决于本机用哪些功能，上游契约要覆盖所有用户。

## 拉上游之后

1. 解决冲突时保留带 `# LOCAL:` 和 `<!-- LOCAL:` 标记的行；`bin/fm-spawn.sh` 里调用行必须仍紧跟在 `freshen_spawn_worktree_base "$WT" || exit 1` 之后，原因见 `bin/local/fm-spawn-setup-lib.sh` 里 `run_spawn_setup_hook` 上方的注释。
2. 运行 `bin/local/fm-agents-trim.sh`；成功就提交生成的 `AGENTS.local.md`，报错就按上一节更新 `PASSAGES` 后重跑。
3. 运行 `grep -rnE '# LOCAL:|<!-- LOCAL:' bin CLAUDE.md`，核对结果与「钩子」一节一致，行号变了就更新本文件。
4. 运行 `bin/fm-lint.sh`，再运行 `bin/fm-lint.sh bin/local/*.sh tests/local/*.sh`：默认的 lint 范围是 `bin/*.sh`、`bin/backends/*.sh` 和 `tests/*.sh`，不包括 `bin/local/` 和 `tests/local/`。
5. 运行 `bin/fm-test-run.sh tests/fm-local-mods.test.sh tests/fm-branch-supervision.test.sh tests/fm-documentation-audiences.test.sh`。
