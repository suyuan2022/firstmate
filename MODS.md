# 本地定制登记

这个仓库是上游 [kunchenguid/firstmate](https://github.com/kunchenguid/firstmate) 的 fork，本文件登记 fork 里所有不提交给上游的本地定制。
定制按「堂前燕」方式组织：上游文件里只留一行钩子，shell 里在行尾或行上标 `# LOCAL: <说明>`，TypeScript 里标 `// LOCAL: <说明>`，Markdown 里标 `<!-- LOCAL: <说明> -->`；定制内容放在只属于本 fork 的独立文件里（`bin/local/`、`docs/local/`、`tests/local/`，Pi 扩展是 `.pi/extensions/local-*.ts`）。
拉上游时，冲突只可能落在下面「钩子」和「清单登记」两节列出的几行上。

行号会随上游改动漂移，以 `grep -rn 'LOCAL:' bin/*.sh .pi/extensions/fm-*.ts` 的结果为准；它列出的行应与「钩子」一节逐条对应。

**每次合入上游之后，都要重新运行 `bin/local/fm-agents-trim.sh` 并提交生成的 `AGENTS.local.md`**，完整步骤见文末「拉上游之后」。

## 钩子

| 上游文件:行 | 做什么 | 定制文件 | 为什么不进上游 |
| --- | --- | --- | --- |
| `bin/fm-spawn.sh:599-600` | 载入 spawn setup 库；599 行是带标记的 `# shellcheck source=` 指令，600 行是 `.` 载入语句 | `bin/local/fm-spawn-setup-lib.sh` | 见下文「spawn setup 钩子」 |
| `bin/fm-spawn.sh:4098` | 在 `freshen_spawn_worktree_base` 之后调用 `run_spawn_setup_hook`，给新分到的 worktree 做项目准备 | `bin/local/fm-spawn-setup-lib.sh` | 同上 |
| `bin/fm-spawn.sh:4936` | 在上游的启动前 export（`GOTMPDIR`、`LAVISH_AXI_HOST` 等）之后调用 `spawn_local_pane_exports`，把本 home 要求的环境变量送进 agent 的 pane | `bin/local/fm-spawn-setup-lib.sh` | 见下文「浏览器改用 Chrome for Testing」 |
| `bin/fm-timeout-lib.sh:23` | 标出头部说明里两段本地句子：`FM_TIMEOUT_MECHANISM_OVERRIDE` 可强制四种机制，以及被信号杀死的命令返回 128 + 信号 | 无，改动留在上游文件里 | 见下文「超时修复」 |
| `bin/fm-timeout-lib.sh:65` | `fm_timeout_mechanism` 的覆盖变量除 `bash` 外也接受 `timeout`、`gtimeout`、`perl`，本机没有该工具时回落到正常探测 | 无，改动留在上游文件里 | 同上 |
| `bin/fm-timeout-lib.sh:180` | perl 兜底机制把被信号杀死的命令报成 128 + 信号，而不是 0 | 无，改动留在上游文件里 | 同上 |
| `bin/fm-branch-prompt.sh:144` | 在监督分支系统提示末尾追加本机 `config/branch-prompt-include.md` 的内容 | `bin/local/fm-branch-prompt-include.sh` | 见下文「监督分支提示追加」 |
| `bin/fm-session-start.sh:616-617` | 在 `AGENTS_START_HASH` 那一段之后载入本地文件；616 行是带标记的 `# shellcheck source=` 指令，617 行是 `.` 载入语句 | `bin/local/fm-agents-refresh-lib.sh` | 见下文「压缩后重印精简版手册」 |
| `bin/fm-watch.sh:227-228` | 在看门程序读取 `FM_*` 时间参数之前载入本地文件；227 行是带标记的指令，228 行是 `.` 载入语句 | `bin/local/fm-watch-env-lib.sh` | 见下文「看门参数」 |
| `.pi/extensions/fm-branch-supervision.ts:1416` | `flushMirror` 发镜像时，有 `globalThis.fmLocalMirrorContent` 就用它生成内容，没有就用上游原来的格式；行尾标 `// LOCAL:` | `.pi/extensions/local-mirror-skill-collapse.ts` | 见下文「镜像不带技能正文」 |

## 清单登记

`docs/documentation-audiences.json` 里有四条本地登记，JSON 不能写注释，所以标记只记在这里：

- `"path": "AGENTS.local.md"` 和 `"path": "AGENTS.override.md"`（第 272、276 行附近），受众 `agent-runtime`。
- `"path": "MODS.md"`（第 292 行附近），受众 `maintainer-architecture`。
- `"path": "docs/local/spawn-setup.md"`（第 380 行附近），受众 `operator-current`。

`tests/fm-documentation-audiences.test.sh` 要求每个被 git 跟踪的 `.md` 文件（包括符号链接）都在这份清单里，少了这些条目测试会失败。

## 只属于本 fork 的文件

这些文件上游没有，拉上游不会冲突：

- `MODS.md` - 本文件。
- `AGENTS.local.md` - 精简版监督契约，由 `bin/local/fm-agents-trim.sh` 生成，第 1 行是 `<!-- LOCAL: -->` 标记，不手改。
- `AGENTS.override.md` - 指向 `AGENTS.local.md` 的符号链接，给 Codex 和 Pi 读。
- `bin/local/fm-spawn-setup-lib.sh` - spawn setup 钩子和 pane 环境变量钩子的全部实现，头部注释是它的完整契约。
- `bin/local/fm-branch-prompt-include.sh` - 读取并输出 `config/branch-prompt-include.md` 的追加段落。
- `bin/local/fm-agents-trim.sh` - 从 `AGENTS.md` 生成 `AGENTS.local.md`，要删的段落清单写在脚本的 `PASSAGES` 里。
- `bin/local/fm-agents-refresh-lib.sh` - 让 Pi 压缩后的手册检查和重印改看 `AGENTS.override.md`，见下文「压缩后重印精简版手册」。
- `bin/local/fm-watch-env-lib.sh` - 读取本机 `config/watch.env` 里的看门参数，见下文「看门参数」。
- `docs/local/spawn-setup.md` - spawn setup 钩子的使用说明和两个环境变量。
- `bin/local/chrome-devtools-mcp-cft.mjs` - 让 chrome-devtools-axi 启动 Chrome for Testing 的转接脚本，见下文「浏览器改用 Chrome for Testing」。
- `.pi/extensions/local-chrome-devtools-cft.ts` - Pi 扩展，给手动启动的 Pi 大副进程设上同一个变量，见同一节。Pi 会自动加载 `.pi/extensions/` 下的文件，所以它不需要钩子。
- `.pi/extensions/local-mirror-skill-collapse.ts` - Pi 扩展，提供镜像钩子调用的改写函数，见下文「镜像不带技能正文」。
- `tests/fm-local-mods.test.sh` - 测试入口 `bin/fm-test-run.sh` 只发现 `tests/*.test.sh`，这个文件依次运行 `tests/local/` 下的全部测试，让它们进入 `--all`、CI 分片和覆盖检查。
- `tests/local/fm-spawn-setup-hook.test.sh` - spawn setup 钩子的行为测试，驱动真实的 `bin/fm-spawn.sh`。
- `tests/local/fm-timeout-lib.test.sh` - 超时修复的行为测试，四种机制逐一强制运行。
- `tests/local/fm-branch-prompt-include.test.sh` - 监督分支提示追加的行为测试，覆盖有文件、无文件、空文件和路径不是普通文件四种情况。
- `tests/local/fm-chrome-devtools-mcp-cft.test.sh` - Chrome for Testing 转接脚本的行为测试：启动模式补上 `--executablePath`、候选优先级、attach 与显式指定时原样放行、找不到 Chrome for Testing 或真正的 mcp 时拒绝；本机装了 axi 时还检查它仍读取 `CHROME_DEVTOOLS_AXI_MCP_PATH`；Pi 扩展只在有开关、有脚本、变量未设时才设置。
- `tests/local/fm-spawn-pane-exports.test.sh` - pane 环境变量钩子的行为测试，驱动真实的 `bin/fm-spawn.sh`：没开关时什么都不发，有开关时在 `GOTMPDIR` 之后发出，工人和二副启动后都带着这个变量。
- `tests/local/fm-agents-trim.test.sh` - 精简脚本的行为测试：段落全部找到、缺段落时报错、`--check` 发现过期，并检查仓库里提交的 `AGENTS.local.md` 与当前 `AGENTS.md` 一致。
- `tests/local/fm-agents-refresh.test.sh` - 压缩后重印的行为测试，用从 `bin/fm-session-start.sh` 取出的真实函数跑：有 `AGENTS.override.md` 时只在精简版变了才重印、印的是精简版；没有时和上游一样。另外钉住被替换的两个上游函数的指纹，上游一改就报。
- `tests/local/fm-mirror-skill-collapse.test.sh` - 镜像改写的行为测试：有开关时技能块换成一行、保留船长自己的话，其他消息和没开关时都和上游一样；并检查钩子行还在。
- `tests/local/fm-watch-env.test.sh` - 看门参数的行为测试，载入真实的 `bin/fm-watch.sh`：没文件时是上游默认值，文件里的值生效，环境变量优先，坏行报出行号并保留默认值。

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
2026-09-24 合入的上游版本仍是旧写法（`exit($? >> 8)`），所以这项修复继续保留。

### 监督分支提示追加

`bin/fm-branch-prompt.sh` 生成 Pi 监督分支的系统提示；监督分支是 firstmate 在 Pi 运行时里专门处理 worker 事件的第二个对话，它写的结果摘要会转给主对话。
钩子仿照上游 `config/brief-include.md` 的形状：本机 `config/branch-prompt-include.md` 不存在或为空时什么都不加；存在时把内容原样放在提示末尾的 `# Home prompt additions` 段落里，前面所有段落优先于它；路径存在但不是可读的普通文件时拒绝生成提示。
「摘要用简体中文」这条要求写在本机的 `config/branch-prompt-include.md` 里，这个文件不提交。
只读取 `FM_CONFIG_OVERRIDE` 或 `FM_HOME/config` 指定的目录，两者都没设时什么都不加；Pi 扩展每次都显式传这两个变量。
改了配置文件后，要等监督分支下次重建（新开主会话，或切换监督分支的模型或推理强度）才生效。
不进上游的原因：语言偏好只属于本机，上游的提示对所有用户保持逐字节稳定。

### 浏览器改用 Chrome for Testing

chrome-devtools-axi 默认用 `/Applications/Google Chrome.app` 启动无头 Chrome。macOS 把这个没窗口的实例当成正在运行的 Chrome，用户点 Dock 图标只会激活它，日常 Chrome 看起来就打不开。
axi 没开放 `--executablePath`，但 `CHROME_DEVTOOLS_AXI_MCP_PATH` 可以指向任意脚本，axi 用 `node <脚本> <参数>` 运行它。`bin/local/chrome-devtools-mcp-cft.mjs` 就是这个脚本：补上 `--executablePath=<Chrome for Testing>` 后交给真正的 chrome-devtools-mcp；attach 模式或已显式指定浏览器时原样放行；找不到 Chrome for Testing 时报错退出，不回落到日常 Chrome。
启用方式是本机开关 `config/chrome-devtools-cft`（空文件，gitignored，不继承，每个 home 各放一个）。有了它：
- `bin/fm-spawn.sh` 的钩子行在启动每个工人、侦察和二副之前，往 pane 里 `export CHROME_DEVTOOLS_AXI_MCP_PATH=<本 checkout>/bin/local/chrome-devtools-mcp-cft.mjs`；
- `.pi/extensions/local-chrome-devtools-cft.ts` 在 Pi 大副启动时给自己的进程设上同一个变量，大副自己用 axi 时也走 Chrome for Testing。
只影响 firstmate 启动的 agent，不改 shell 配置。环境里已经设了这个变量时以已有的为准。开了 `config/launch-env-allowlist` 的 home 要把 `CHROME_DEVTOOLS_AXI_MCP_PATH` 加进白名单。Claude 大副不在覆盖范围内。已经在跑的 axi bridge 要 `chrome-devtools-axi stop` 后才换。
不进上游的原因：Chrome for Testing 的位置（agent-browser 或 Playwright 的下载目录）只属于本机。

### 精简版 AGENTS

上游 `AGENTS.md` 是每个 firstmate 会话都要全文加载的监督契约，其中有本机用不到的内容。
`bin/local/fm-agents-trim.sh` 读上游 `AGENTS.md`，按整行删掉下面几组内容，生成 `AGENTS.local.md`：

- (a) Relay（公开提及集成）：第 14 节全部、第 8 节里两句只讲 Relay 的句子、第 13 节的 `fmx-respond` 条目、第 2 节目录清单里 7 行 Relay 生成文件。
- (b) 本机不用的运行时和工具：第 2 节里 grok、kimi、gemini、muse、cursor、devin 的任务状态文件行，`.cursor-park-owner`、`config/cmux-socket-password`、`mail.check.sh` 和 `.mail-*` 各行；第 13 节的 `firstmate-orca`、`firstmate-codexapp` 条目。
- (c) 调度候选数组：第 4 节从「Firstmate alone resolves a matched profile array」到「Load `quota-array-dispatch` ...」的 10 行，以及第 13 节的 `quota-array-dispatch` 条目。
- (d) 本机没用的可选配置开关：第 2 节的 `config/claude-account config/pi-account`、`config/supervision-host`、`config/trace-context`、`config/fleet-ledger`、`config/wedge-defer-parked-gate`、`config/watched-tools.json` 各行。开关本身靠 `config/` 下有没有文件生效，删的只是手册里的介绍；要用哪个，把它从清单里删掉再重跑。
- (e) 脚本自己读写的内部记录：第 2 节 11 行，如 `<id>.progress`、`<id>.merge-authority`、`.startup-network.*`、`.<id>.open-decisions-cursor`。标着「never touch」的行都保留，它们是防止大副手动删文件的警告。
- (f) 第 3 节逐段描述启动摘要格式的第 1、2、5、6、7 步。摘要自己每段有标题；里面的规则在第 3 节开头和第 5、7、8 节都有。第 3、4 步（唤醒队列、监督说明）保留。
- (g) 第 4 节「写好说明后先跑 `bin/fm-dispatch-resolve.sh`」那一句。本机 `.env` 没有 `TYPESAFE_API_KEY`，它每次都返回 `off`；配了 key 再把这条删掉。
- (afk) 离开模式的两行索引：`config/wedge-alarm` 和 `afk-contracts/`。`/afk` 会加载自己的技能，里面有全部规则；不配 `config/wedge-alarm` 时告警默认弹 macOS 通知。要认真用离开模式时，把这一组整组删掉再重跑。

no-mistakes 的流程说明一律保留；(d) 只删了 `config/wedge-defer-parked-gate` 这一行开关介绍，因为本机不用那个关卡。
逐条清单的唯一出处是脚本里的 `PASSAGES`；每条都锚定在所属章节里，必须恰好匹配一次，区间还固定了行数。
上游改动让任何一条找不到、匹配多处或行数变了，脚本就列出全部问题、什么都不写、以非零退出，这时对照新的上游文本更新 `PASSAGES` 再重跑。
`bin/local/fm-agents-trim.sh --check` 只检查 `AGENTS.local.md` 是否与当前 `AGENTS.md` 生成的结果一致，不写文件。

各运行时这样加载精简版：

- Claude Code：仓库里的 `CLAUDE.md` 保持上游原样，因为 CI 的「Repo invariants」检查要求它是标准的 `@AGENTS.md` 指针。
  本机另用两处不提交的配置让 Claude 改读精简版：`CLAUDE.local.md`，内容只有一行 `@AGENTS.local.md`；`.claude/settings.local.json` 里的 `"claudeMdExcludes": ["/Users/suyuan/firstmate/CLAUDE.md"]`，让 Claude 不再加载完整版。
  两个文件都列在 `.git/info/exclude` 里，只在 main 上已有 `AGENTS.local.md` 之后（即本改动合入之后）才添加，否则 Claude 两份契约都读不到。
- Codex 和 Pi 在同一目录下优先读 `AGENTS.override.md`，读到的就是 `AGENTS.local.md` 的全文；它们原样读取、不展开 `@` 导入，所以这里用符号链接而不是一行指针。
- 其他运行时（opencode 等）仍读完整的 `AGENTS.md`。

本机全局 gitignore（`~/.config/git/ignore`）有 `*.local.md` 规则，`AGENTS.local.md` 是用 `git add -f` 纳入跟踪的；已跟踪的文件不受忽略规则影响，重新生成后照常 `git add` 即可。

不进上游的原因：删掉哪些内容取决于本机用哪些功能，上游契约要覆盖所有用户。

### 压缩后重印精简版手册

Pi 大副压缩上下文后，`bin/fm-session-start.sh` 会检查手册有没有变；变了，或者没法确认会话启动时读的是哪一版，就把整份手册重印进对话，并注明「以这份为准」（上游 e8c76458，#2163）。
上游检查和重印的都是 `AGENTS.md`，而本 fork 的 Pi 读的是 `AGENTS.override.md`，也就是精简版。不改的话，一触发就把完整版塞回来，精简白做；只改删除清单时又永远判成「没变」。
`bin/local/fm-agents-refresh-lib.sh` 在有 `AGENTS.override.md` 时，把会话启动时记的指纹、压缩后的比对和重印都改用它，没有时和上游完全一样。它替换了上游的 `agents_baseline_drifted` 和 `print_agents_refresh_if_required` 两个函数，只换了读哪个文件和说明文字；`tests/local/fm-agents-refresh.test.sh` 钉住了这两个上游函数和 `AGENTS_START_HASH` 那一段的指纹，上游一改就报错，要对照新代码核对本地文件后再更新指纹。
只影响 Pi 和 pi-signed 的压缩路径；Claude 重置时自己会重读，不走这里。
合入后第一次压缩会重印一次：旧的启动指纹是按 `AGENTS.md` 记的，和精简版对不上。之后恢复正常。
不进上游的原因：上游没有 `AGENTS.override.md` 这一层。

### 镜像不带技能正文

Pi 大副会把船长和大副的对话抄给监督分支（`fm-main-mirror`），让分支知道船长刚说了什么。其他消息截到 4000 字，船长当前那条原样全抄（上游 #3211）。
船长在 Pi 里打 `/afk`、`/stow`、`/bearings` 这类命令时，Pi 把整本技能正文展开成船长的消息，于是两三万字的技能正文原样进了分支，之后分支每处理一次唤醒都要重读（9/19–9/23 共 23 条、约 12.4 万 token，被重读约 17.4M）。分支自己的提示词里有离开模式的规则，也读 `state/.afk-contract` 判断姿态，用不上这些正文。
`fm-branch-supervision.ts` 的钩子行在发镜像时，如果有 `globalThis.fmLocalMirrorContent` 就用它生成内容，否则照上游写 `[tag] text`。`.pi/extensions/local-mirror-skill-collapse.ts` 在本机开关 `config/branch-mirror-collapse-skills` 存在时装上这个函数：船长的消息如果正好是一个 Pi 技能块（后面可以跟船长自己的话），就换成 `[captain] ran /<技能名>` 加上那些话；其他消息一律照上游。
用全局函数而不是 import，是因为上游的类型检查测试（`tests/fm-pi-primary-types.test.sh`）只拷贝它认识的扩展文件，import 本地文件会让它找不到模块。
大副自己的对话、大副读到的技能全文都不变。开关不继承，改了要等 Pi 重新加载扩展才生效。
不进上游的原因：镜像里留多少技能正文是本机的取舍。

### 看门参数

看门程序的时间参数（多久没动静算「可能卡死」、声明在等的任务多久复查一次等）在上游只能靠环境变量设；看门程序由 Pi 扩展或 Claude 钩子启动，没有地方 export。
`bin/local/fm-watch-env-lib.sh` 在看门程序读这些参数之前，读本机 `config/watch.env`（gitignored，不继承，每个 home 各放一份）。
- 只认 `FM_PAUSE_RESURFACE_SECS`、`FM_STALE_ESCALATE_SECS`、`FM_TURNEND_CHURN_ABSORB_SECS`、`FM_BUSY_TURN_MAX_SECS` 四个参数，值必须是不以 0 开头的正整数。
- 环境里已经设了的以环境为准。
- 未知参数、坏值、没有 `=` 的行，都在 stderr 报出行号后跳过，这一项保留上游默认值；文件写坏不会让看门程序起不来。
只有 `bin/fm-watch.sh` 读这个文件；离开模式的后台进程 `bin/fm-supervise-daemon.sh` 也读 `FM_PAUSE_RESURFACE_SECS`，但它不读这个文件。
改了要等看门程序重启才生效。
不进上游的原因：参数取值是本机的取舍，上游已经提供了环境变量这个入口。

## 拉上游之后

1. 解决冲突时保留带 `LOCAL:` 标记的行；`bin/fm-spawn.sh` 里 `run_spawn_setup_hook` 调用行必须仍紧跟在 `freshen_spawn_worktree_base "$WT" || exit 1` 之后，原因见 `bin/local/fm-spawn-setup-lib.sh` 里 `run_spawn_setup_hook` 上方的注释；`spawn_local_pane_exports` 调用行必须仍在上游启动前 export 那一段里、发送启动命令之前；`bin/fm-session-start.sh` 的载入行必须仍在 `AGENTS_START_HASH` 那一段之后；`bin/fm-watch.sh` 的载入行必须仍在 `POLL=${FM_POLL:-15}` 之前。
2. 运行 `bin/local/fm-agents-trim.sh`；成功就提交生成的 `AGENTS.local.md`，报错就按上一节更新 `PASSAGES` 后重跑。
3. 运行 `grep -rn 'LOCAL:' bin/*.sh .pi/extensions/fm-*.ts`，核对结果与「钩子」一节一致，行号变了就更新本文件。
4. 运行 `bin/fm-lint.sh`，再运行 `bin/fm-lint.sh bin/local/*.sh tests/local/*.sh`：默认的 lint 范围是 `bin/*.sh`、`bin/backends/*.sh` 和 `tests/*.sh`，不包括 `bin/local/` 和 `tests/local/`。
5. 运行 `bin/fm-test-run.sh tests/fm-local-mods.test.sh tests/fm-branch-supervision.test.sh tests/fm-documentation-audiences.test.sh tests/fm-session-start.test.sh tests/fm-pi-branch-extension.test.sh`。`tests/local/fm-agents-refresh.test.sh` 报指纹变了时，对照上游新代码核对 `bin/local/fm-agents-refresh-lib.sh`，再更新测试里的指纹。
