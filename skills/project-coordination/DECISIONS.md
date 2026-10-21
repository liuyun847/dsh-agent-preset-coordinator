# 预设行级决策（历史档案）

来源：`project-coordination` 技能原「一之二、逐行保留/移除决策」节（该节号已取消）。
当时用户要求"决定移除哪些功能"，这里是可复核的落点。派生的基线是自带 `standard` 预设，
与上游的行级对照见同目录 `BASELINE.md`（差异数字可用 `tools/preset_diff.ps1` 重算）。

> 2026-09-24 迁移后，本包的组合文件是 `presets/coordinator.patch.yml`（bundle 声明行形态）。
> 更早条目里的 `agent.cordis.yml` 是同一文件的历史名称，其中的行数 / 字节数为**当时实测**，
> 不随改名重算；两条现行指引（耦合约束锚点、世代键口径）已按现名更新。

> 本文件**不被技能扫描器读取**（扫描器只认技能根下第一层的 `<名字>/SKILL.md` 或 `<名字>.md`），
> 只在"要改预设插件行"时人工查阅。改行前请先看 `SKILL.md` 同名节保留的耦合约束警告。

| 行 | 决定 | 依据 |
|---|---|---|
| `persona` | 改写 | 本预设核心：铁律（永不阻塞 / 委派而非执行 / 共享上下文 / 用户视野） |
| `persona`（新增【目标】块） | 新增 | 内容：在人格首段与铁律一之间插入一行——「【目标】保持上下文干净、随时响应用户：这是下面四条铁律的由来——重活交给子代理与后台作业，你的上下文只留计划、结论与在飞事项；上下文越干净，越能随时接住用户的新指令。」依据：用户 2026-10-05 要求把「目标是保持上下文干净、随时响应」写进预设提示词。同批置换（R2）：goals 段 4 行归属注释并成 1 行、"watch: false" 变更日志 13 行压成 2 行指针——yml 423 行 / 32174 字节 → 411 行 / 31061 字节，预算门由 FAIL 回 PASS；因果见本文件「watch: false 因果档」一节 |
| `tool-ralph` | **移除** | 前台阻塞循环（一轮一个全新代理，默认上限 256 轮），会卡住协调者数小时；且与 continuable + goal 语义重叠，规范要求"仅人类明确要求时使用" |
| `workflow-worker-thread`、`tool-workflow` | **移除** | 前台阻塞调用，与铁律一直接冲突；且自带常驻 prompt 段劝导用它，与人格对打 |
| `tool-subagent`、`tool-subagent-fork` | 改用 `agentPreset` | 0.2.1 删除了委派行的 `persona` / `toolFilter`：传了就抛错，整次预设挂载被拒。隔离改由独立预设承担 —— spawn 行 `agentPreset: executor`（定义在同包 `presets/executor.patch.yml`：「执行子代理」人格 + 工具面减去全部委派行；2026-10-22 前临时挂在 profile 的 `cordis.patch.yml`）；fork 后端 `inheritsParentContext`，拿不到独立预设，只能继承协调者人格，故加 `maxDepth: 1` 收紧递归。机理见锚点 `[anchor: subagent-preset]`，此处不复述。⚠ 两份 patch 由 `package.json` 的 `dsh.bundle.patch` 数组一起装载：挪走或删掉 executor 那份，本预设在挂载期因 `Unknown agent preset` **整份激活失败**（不是静默降级） |
| `skill-filesystem` | 加 `customSkillDirs` | 让协调协议随预设走 |
| `tool-bash`、`tool-pwsh`、`tool-fs`、`tool-fs-search` | **保留** | 子代理与协调者共享工具面（**委派工具除外**，见上一行）；删掉等于子代理没法干活 |
| `tool-jobs` | 保留 | 后台命令的收集与终止 |
| `tool-subagent-control`、`list-agents` | 保留 | 无阻塞协调的双向通道 |
| `tool-goal`、`command-goal` | 保留 | 跨轮次长目标 |
| `tool-todo` | 保留 | 计划的可视化；已配 `allowParallelInProgress: true` 适配并发 |
| `tool-ask-user` | 保留 | 需求不明时向用户确认，比自行假设安全 |
| `tool-web` | 保留 | 调研子代理常用 |
| `present` | 保留 | 交付物展示 |
| `plan-mode`、`compaction`（3 行） | 保留 | 计划模式与长会话压缩，对长项目必要 |
| `agent-instructions` | 保留 | 共享上下文靠它加载 AGENTS.md 链 |
| `tool-subagent-codex`、`claude-code` | 保持禁用 | 可选外部 provider 未安装 |

- **早期条目已归档**：2026-09-14 / 09-17 / 09-20 / 09-21 四条已移出主文档（内部归档，不随包发布）；主文档只留现行规则与近期条目。

- **2026-09-23 · 手册瘦身：身份声明并入 description、Cursor 对照整节移到包根 README**：三件事同轮完成——① `SKILL.md` 正文开头那两行「只给协调者用」身份声明并入 frontmatter `description`（值改为身份句 + 原摘要，一个字符不改地拼接）；② 「一、这套做法靠什么成立」整节（Cursor 对照表 + 「DSH 里没有对应物的」清单）搬到包根 `README.md`，落点：`## 文件` 表格之后、`## 必须知道的约束` 之前，标题改写为「与 Cursor Projects 的对照（为什么不需要重造轮子）」，节内两处指向手册节号的交叉引用改成自足表述（指向 `skills/project-coordination/SKILL.md`）；③ 原「一之二、改预设插件行前必看」重编号为「一」，后续节号（二～八）保持不动。
  - 置换（R2：净行数 ≤ 0）：`SKILL.md` 净减 **27 行**、字节 28703 → 26047；`README.md` 增 **24 行**、字节 2740 → 5499；两文件合计净减 3 行。README **不在** `tools/preset_check.ps1` 的比对源内（预算门只收 `agent.cordis.yml` / `BASELINE.md` / `DECISIONS.md` / `preset.yml`，重复门另加不设预算的 `SKILL.md` / `context.md` / `ANTI-BLOAT.md`），故移入的整节不再进这两道门；`SKILL.md` 移出后仍受重复门约束。
  - 依据：用户要求把 Cursor 对照与身份声明移出手册——对比内容属**设计沿革**，只该按需查（放 README，改 yml 时人工读到，不必占手册篇幅）；身份声明进 `description` 才能让技能目录里的子代理**一眼看到「不适用」**（手册正文要加载后才可见）。重编号的依据：避免出现「没有『一』、却从『一之二』开始」的悬空编号。

- **2026-09-23 · 生效口径改准（README 第 47 行那条）**：原表述「只改 `skills/` 下的文件或资产，要等组合文件本身变动、或进程重启，才会进新会话」把上游 Known Limitations 的「代际只以组装文件为键」——那是**组装层面**（工具面 / 提示词段落 / 插件行）的世代键——推广成了「技能内容改完不生效」，与本会话实测冲突：改 `skills/project-coordination/SKILL.md` 的 frontmatter `description` 后，当前会话的技能目录当场显示了新描述，无需新建会话、无需重启进程。新表述分两层：① 工具面 / 提示词段落 / 插件行由 `presets/coordinator.patch.yml` 决定，世代戳只认它，改它只对改动后新建的会话生效；② 技能文件内容不在世代键里，走 `dsh-skill-filesystem` 的目录监视，对已在运行的会话生效。
  - 置换（R2）：同一条目改写、无新增事实——README 该条 1 行 → 3 行（净 +2 行）；README 不在本包门禁的比对源内（预算门 4 份 targets，重复门另加 `SKILL.md`），故不进两道门。
  - 依据：上游 `dsh-agent-presets` 的 `README.zh.md` 第 176–177 行（「代际只以组装文件为键」；第 177 行「`dsh-skill-filesystem` 默认监听自己的根目录……每一轮『编辑后建会话』都会新增一套活的 watcher」已把技能监视与世代键分开叙述）；`dsh-skill-filesystem/lib/index.js` 的 `isRelevantWatchEvent`（`<root>/<name>/SKILL.md` 的 `change` 与直属 `addDir`/`unlinkDir` 均触发失效）；`dsh-tool-skill/lib/index.js` 第 203-236 行的 `agent/pre-step` 目录快照与整份替换目录；`dsh-skill-filesystem/README.zh.md` 第 81 行（「新增、改名或删除 skill（或编辑其 frontmatter）会在下一个模型步骤触发目录刷新」）；本次实测（2026-09-23）。

- **2026-09-24 · 迁移为 bundle 声明行（旧目录预设形态废弃）**：dsh 升级 `0.1.7-rc.1`，旧 `.agent-presets\coordinator\` 目录不再被读取（`dsh-agent-presets` 包已随新版移除）；本包改为组合包 `dsh-agent-preset-coordinator`：`presets/coordinator.patch.yml` 一行 `@deepseek-ai/dsh-agent-preset` 声明（`config.id: coordinator`，**与旧目录名相同 ⇒ 旧会话仍能按 id 恢复**），子插件列表移入 `config.plugins`（逐行原样，含全部注释与 isolate 组）；`preset.yml` 的 name / description 移入 `config.name` / `config.description`，新增 `order: 2`（standard 为 1）。skills / tools / ANTI-BLOAT.md 随包走；profile 的 `dsh.profile.bundles` 由 dshpm 校正加入本包。
  - **skills 挂载换官方写法**：`customSkillDirs` 由旧的 `new URL('skills/', baseUrl)`（baseUrl = 预设目录）改为官方 rc.1 形式 `createRequire(baseUrl).resolve('dsh-agent-preset-coordinator/package.json')` 再 join `skills`（baseUrl = profile 目录）——挂的是 node_modules 副本，本包与源码同 inode，**原地改即两侧生效**；用 write/edit 这类换文件式写入会断链，改完核 fileId，断了就重建。
  - **tools 三脚本改造**：`preset_check.ps1` 预算表改指 `presets\coordinator.patch.yml`（420 行 / 32000 字节）、去掉 `preset.yml` 条目；`preset_diff.ps1` 基线改为 web-app bundle 的 `presets/standard.patch.yml`（差异口径重算为 131 → 172、+59 / −18），并新增"块标量内容按基准缩进归一化"（纯缩进风格差异不计入）；`validate_yaml.py` 支持 bundle patch 形态（声明行结构 + `config.plugins` 递归统计），锚点校验路径与文件名集合同步。
  - 置换（R2）：本条不新增预设行（patch 内容 = 旧组合文件逐行 + 新头部说明 + 声明行包装）。
  - 依据：上游 rc.1 的 `dsh-agent-preset` / `dsh-agent-preset-registry` README.zh.md 与 `editing-cordis-compositions` 技能「Migrate a legacy preset」节；官方 `dsh-web-app` 的 `presets/cordis.patch.yml`（skills 挂载与 isolate 写法的 rc.1 范例）；本次实测（`--dump-config`、预设选择器、旧会话恢复、patch-guard 重打）。

- **2026-09-25 · 内存载体：`context.md` 文件 → 任务板工具 `task_board`（用户决议：文件只增无出口，落盘还会造出第二份记忆）**：在飞事项改由工具承载（不落盘、dsh 重启即空、按项目根分桶、超硬顶即拒写）；旧文件与"两区"模板退役，`preset_check.ps1` 随之删掉该包外目标与 `-Workspace` 参数；长期结论落点不变。口径见 README「防膨胀设计」。

- **2026-09-26 · 任务板存储：纯进程内存 → 宿主领域存储持久化（用户决议：板子要跨 dsh 重启存活）**：`task_board` 改为**内存为权威读源 + 宿主领域存储持久化**——域 `task_board` v1 / 表 `boards`，一块板一条记录，落 `%USERPROFILE%\.dsh\storages\task_board.json`，每次写先落盘再生效 ⇒ **跨 dsh 重启存活**。**降级行为**：宿主存储服务不可用或打开失败时，插件打一行警告并退回纯内存态，**那时"重启即空"仍成立**（措辞不得写成"永不丢"）。其余性质不变（按根会话分桶、只对本预设的会话与子代理开放、单字段输入硬顶、板内条数与板子数量无上限）。**会话日志路线已评估并否决**：写未知事件类型会让整段会话下次拒读（fail-closed），插件的写入面无法设置 ignorable，官方实验包靠构建期静态白名单。口径见 README「防膨胀设计」。

- **2026-10-05 · `watch: false` 因果档（自 `presets/coordinator.patch.yml` 移出，原位置已换成 2 行指针）**：yml 里只留可操作结论——**`watch: false` 别删**（与宿主级那行同步，修「技能目录整场不下发」）；回滚 = 删掉 `skill-filesystem` 行 config 里的 `watch: false` 一行即可。因果压缩如下（原块 13 行，2026-09-28 加入时撰写）：
  - 病灶：`dsh-tool-skill` 的 `agent/pre-step` 第一道门是 `if (!snapshot.complete) return decision;` ⇒ `complete=false` 时这一步既不下发也不重发技能目录，每个步骤都为假 ⇒ 整场会话都没有 `<available_skills>`。
  - 三条置假之路（`dsh-skill` 的 `collect()`）：① provider 自报不完整（本机只有 `dsh-skill-filesystem`：`watchManager.observeRoots()` 起 watcher 抛错时它 catch 住并置 `complete=false`）② provider 的 `list()` 抛错 ③ collect 期间 revision 变了两次的竞态。
  - 作用面：关掉 watcher 后 `retainRoot()` 不再 `ensureWatcher()`（`if (this.config.enabled)` 直接跳过）⇒ ① 整条消失；宿主里"文件一变就 `invalidateCache()`"的频率也大幅下降 ⇒ ③ 几乎不可能。
  - 代价（明确接受）：本行技能目录（随包的 `skills/`，即 `project-coordination`）的实时热更新失效——改完技能文件要等下一次会话/重启才在目录里刷新；改技能**内容**（正文）本来就要重新加载，而"某个技能整个消失/新增"在本包内极少发生。

- **2026-10-22 · executor 预设并进包（发布阻塞项收口，A 方案：并进包而非 README 手工补装）**：`preset-executor` 从 profile 的 `cordis.patch.yml` 搬进本包，单开 `presets/executor.patch.yml`；`package.json` 的 `dsh.bundle.patch` 改成数组两项（executor 在前、coordinator 在后，与依赖方向一致），profile 里只留 3 行指针。公开包的阻塞点就此消失：单装本包即可解析 `agentPreset: executor`，不再要求用户先手改 profile。
  - 为何单开而不并进 `coordinator.patch.yml`：那份压着 420 行 / 32000 字节的「每轮注入」硬顶（并入前 388 / 29141），并进去必超限；executor 只在 executor 会话注入人格，成本面不同，故给它独立的 130 行 / 7500 字节硬顶（`preset_check.ps1` 预算表同步）。
  - 连带：`validate_yaml.py` 默认同时校验两份 patch、锚点定义集合取两份并集。作者本机的预设里另挂了一行 `ptc-lazy-sdk`（按需注入工具签名的插件，未单独发布），公开版不含该行，其余插件行与本机一致（见 README「必须知道的约束」）。
  - 依据：上游 `dsh-app-boot/lib/index.js` 的 `bundlePatchFiles()` 接受「一个路径或一组有序路径」，`cordis-plugin-include` 的 `applyEntryPatches` 在 `insert` 无 id 时把行追加到组合末尾 ⇒ 数组顺序即声明顺序；本次实测：`validate_yaml.py` 两份均 OK、`preset_check.ps1` 预算门 PASS、临时 profile（bundles 含本包）跑 `--dump-config` 显示 `preset-executor` 与 `preset-coordinator` 同层装载且无报错。
