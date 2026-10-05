# dsh-agent-preset-coordinator 组合包

DSH「项目协调者」预设的 **bundle 组合包**：只委派、永不阻塞的协调型 Agent。

2026-09-24 由旧目录预设（`~\.dsh\.agent-presets\coordinator\`）迁移而来 —— dsh 0.1.7-rc.1 起
预设是普通 Cordis 组合里的声明行，本包以 bundle patch 形式出货（旧目录不再被读取）。

## 配套包：任务板工具

随包技能（`skills/project-coordination/SKILL.md`）把**共享任务板**当协调者的工作内存用 —— 那个
`task_board` 工具**不在本包里**，由配套包
[`liuyun847/dsh-host-task-board`](https://github.com/liuyun847/dsh-host-task-board) 提供（DSH 宿主插件，
落宿主领域存储、跨 dsh 重启存活）。**两个包成对使用**：本包给出 preset id `coordinator`，
任务板插件的角色门只放行该预设的会话及其子代理（其它预设拿到明确拒绝）；缺了任务板插件，
技能里「二、共享上下文 = 任务板工具」整节与 R0 移出机制都无处落地。

## 文件

| 路径 | 作用 | 何时读 |
|---|---|---|
| `presets/coordinator.patch.yml` | **组合本体**：一行 `@deepseek-ai/dsh-agent-preset` 声明（`config.plugins` = 工具面、人格、隔离域） | 改插件行时 |
| `skills/project-coordination/SKILL.md` | **操作手册**：三种模式、委派模板、共享上下文（任务板工具 `task_board`）用法、R0 移出机制、并发边界、面向用户的呈现 | 模型按需加载 |
| `skills/project-coordination/BASELINE.md` | 与上游 `standard` 的差异对照（历史档案） | 改 yml 时人工查 |
| `skills/project-coordination/DECISIONS.md` | 逐行保留/移除决策（历史档案） | 改 yml 时人工查 |
| `tools/preset_diff.ps1` | 与上游基线的差异重算（只读） | 改 yml 后 |
| `tools/validate_yaml.py` | YAML 语法 + 声明行结构 + 命名锚点校验（只读） | 改 yml 后 |
| `tools/preset_check.ps1` | **防膨胀检查**：预算门（行/字节硬顶）+ 重复门（≥4 行段落精确哈希） | 改任何文件后 |

## 安装

在 profile 目录下（含 profile `package.json` / `dsh.profile.bundles` 的那个目录，例如
`%USERPROFILE%\.dsh\profiles\desktop`）安装：

```powershell
cd <profile 目录>\plugins           # 例：%USERPROFILE%\.dsh\profiles\desktop\plugins
git clone https://github.com/liuyun847/dsh-agent-preset-coordinator.git
cd ..
dshpm add file:./plugins/dsh-agent-preset-coordinator --profile desktop
```

本包**不发布到 npm**，按 `file:` / `link:` 本地安装；它自身不含代码依赖，只声明 `dsh.bundle.patch`。
配套的任务板插件用同样方式装（见上一节）。

- **bundles 校正**：本包声明了 `dsh.bundle.patch`，`dshpm sync` 会把它收进 `dsh.profile.bundles`（判据：能解析 + 有 patch）。
- **生效**：组合本体（`presets/coordinator.patch.yml`）在**宿主进程启动时**一次性读入，**不重启宿主不生效**（连新建会话也拿不到）；重启后只对**新建**会话生效。完整口径见「改动何时生效」一节。
- **skills 挂载的是 node_modules 副本**（`createRequire(baseUrl)` 解析包目录，不是 `plugins\` 下的源码目录）；技能正文的改动对已在运行的会话也生效。

### 改包内文件前先看（本地 `file:` 安装的两个坑）

- **宿主实际加载的是运行副本**：`<profile 目录>\node_modules\dsh-agent-preset-coordinator\`。
  `file:` 依赖在 pnpm 下**可能是硬链接、也可能是实体拷贝**（同一台机器逐文件都不同）⇒
  判据是**逐文件实测 `fileId`**，别一概而论；任何情况下都核对两侧 SHA256。
- **别用会"换文件"的写入方式改本包文件**：写临时文件再改名的编辑器会**打断硬链接** ——
  运行副本侧从此留旧内容且不再跟改。改完必须复核两侧 `fileId`（`fsutil file queryfileid`），
  不同就用 `New-Item -ItemType HardLink` 重建运行副本侧那条。
- **新增文件不会自动进运行副本**：需重跑 link（profile 目录下重新执行上面的 `dshpm add`）；
  `dsh.bundle.patch` 指向的文件变化需重装并重启。

## 与 Cursor Projects 的对照（为什么不需要重造轮子）

DSH 的原生机制已经覆盖了 Cursor Projects 的大部分能力，不需要新造轮子：

| Cursor Projects 的能力 | DSH 对应机制 | 状态 |
|---|---|---|
| 协调者只委派、永不被卡住 | `subagent` 的 `backgroundMode: continuable` | 调用立即返回子代理 id，不等结果；协调者前台始终空闲，用户随时插得进话 |
| 子代理完成通知 | 服务自带结算通知 | 子代理 Activation 结束时自动送达父代理，含其最终回复 |
| 父→子追加指令 | `send_message` | 在运行中子代理的下一个步骤边界插入 |
| 全局掌握所有子代理 | `list_agents`（`children` / `descendants`） | 状态 running / idle / ready |
| 叫停跑偏的子代理 | `interrupt_agent` | 只停当前轮，子代理本身保留可续 |
| 大批量扇出 | 一条消息里并发多次 `subagent` 调用 | **不要用 `workflow`**：前台阻塞，本预设已移除它 |
| 跨轮次长目标 | `create_goal` + goal round driver | 目标在多轮之间持续推进 |
| 共享上下文 | 跨轮次记忆 = `task_board` 任务板（在飞，内存 + 宿主存储）+ 项目文档（知识库）二者分工 | 任务板按**根会话**分桶（**没有 `project` 参数**；同一顶层会话及其任意深度的派生会话共用一块）、对协调者与其子代理开放；每次写都先落进 DSH 宿主存储（域 `task_board`，`~\.dsh\storages\task_board.json`），**跨 dsh 重启存活**（宿主存储不可用时降级为纯内存态，那时重启即空）；子代理自动继承 cwd 与 `AGENTS.md` 指令链 |
| 定时触发 | `schedule_create` | 会话内提醒，会话不存活时会积压 |

**DSH 里没有对应物的**（不要假装有，也不要向用户暗示能做到）：

- **云端独立计算机**。所有子代理都跑在同一个本机 Node 进程里。合上笔记本，一切停止。
- **数千个并发子代理**。真实边界见 skills/project-coordination/SKILL.md 的「六、并发与成本的真实边界」。
- **设备级隔离**。电脑控制、前台窗口、Godot 运行时都是全机唯一资源，没有 per-agent 实例；两个子代理同时用会互相破坏（不排队、也不报错）。**唯一可靠**的办法是协调者串行派活——见 SKILL.md「六、并发与成本的真实边界」里的「独占资源必须单飞」。**没有工具层兜底，只能靠纪律**。
- **Slack / PR 自动订阅**。唯一的自动触发是会话内的 `schedule_create`，它**由 profile 注入、非预设自带**：若当前会话没有这个工具，说明 profile 未挂 `dsh-schedule`，改用 `create_goal`。它也只对加载之后新建的会话生效，子代理拿不到。
- **前台阻塞的 `workflow` / `ralph`**。本预设已移除这两个工具：整段跑完才返回，会卡住协调者（ralph 尤其严重，一轮一个全新代理）。批量编排改用并发 `subagent`；"反复尝试直到成功"用 `create_goal` 跨轮推进。用户明确点名 Ralph 时，告诉他要恢复需在预设里取消注释。

## 必须知道的约束

- **`tools/preset_check.ps1` 必须保持 UTF-8 with BOM**。无 BOM 时 Windows PowerShell 5.1 会把中文按 ANSI 解码，抛语法错误并 Exit 1（已实测）。**编辑工具会抹掉 BOM**——保存后须用 `[System.IO.File]::WriteAllText($p, $text, [System.Text.UTF8Encoding]::new($true))` 复原，并自验前 3 字节是 `EF BB BF`。
- **上限只保留给"每轮注入"的文件**：硬顶 420 行 / 32000 字节只压在 `presets/coordinator.patch.yml` 这一份上。按需加载的长文档（`SKILL.md`）**不设上限**，由"完成即移出"（R0）与重复门治理——不要事后给它补上限。任务板 `task_board` 的落盘副本由宿主领域存储承担（`~\.dsh\storages\task_board.json`），它不是文档、不进这两道门；只有工具自带的**单字段输入硬顶**（描述 8,192 B / 标题 200 B / 依赖 16 条 / 写范围 8 条，超限**拒绝写入**）——**板内条数与板子数量没有上限**（增长型上限已整体取消，2026-09-25）。
- **改动何时生效**（2026-09-24 迁移后口径）：① **工具面 / 提示词段落 / 插件行**由 `presets/coordinator.patch.yml` 决定，世代戳只认它。该文件在**宿主进程启动时**由 `dsh-app-boot` 用 `readFileSync` 一次性读入，这条路径**没有任何文件监听**；组合唯一的「热重载」通道 `dsh-hmr` 只监听三处——profile 的 `cordis.patch.yml`、`~\.dsh\cordis.patch.yml`、profile 的 `package.json`——重读判据 =「`dsh.profile.bundles`（从 package.json 取）+ 两份 patch 文件全文」：两份 patch 任一内容变化即重读整棵树，`package.json` **只有 `bundles` 真的变了才算**（其余键改了会提前 return、不重读；依据 `dsh-hmr/lib/index.js` 353-376 行）。⚠ 该判据有个陷阱：hmr 记的「上次 bundles」是**实际装载成功**的层名单，而每次比对读的是 manifest 的原始数组，有 bundle 被跳过或顺序变化时两者不等 ⇒ 此时改 `package.json` 的任意键都会越过"只有 bundles 变了才算"的提前返回、意外重读整棵树。本包的 yml 既不在监听集也不在判据里 ⇒ **不重启宿主 dsh，连新建会话也拿不到新文本**；重启后只有**新建**会话用新提示词，已在跑的会话保持自己那一代继续跑。（附带效果：此后若改了 profile 的 `cordis.patch.yml` 或 `~\.dsh\cordis.patch.yml`，`dsh-hmr` 会整份重读组合，本包的新文本会顺带生效；改 `package.json` 则只有动 `bundles` 才有同样效果——都不是改本文件的可靠路径。）② **技能文件内容**（`skills/` 下的 `SKILL.md` 等）**不在世代键里**，走 `dsh-skill-filesystem` 的目录监视：改 frontmatter / 增删技能在下一个模型步骤就刷新技能目录，改正文则下次加载即读到新内容——都对**已在运行的会话**生效，无需新建会话或重启进程（前提：改动确实落在运行副本里；本包同 inode，原地改即两侧同时变）。
- **旧目录形态已废弃**：`~\.dsh\.agent-presets\` 下的 `coordinator\` 等目录 rc.1 起不再被读取；本包就是权威副本。`team-coordinator` / `teamlab` 两份目录暂未迁移（Team 方向已终止，去留未定）。

## 防膨胀设计

完整设计档（分层预算、移出映射表、工具规格、判定标准）属**内部治理档，不随本包发布**；对外可用的
就是 `tools/preset_check.ps1` 的双门检查（预算门 + 重复门）与下面三条护栏。

三条护栏速记：**R1** 一事实一主副本（权威副本恰好一处 + 其余为指针）· **R2** 准入即置换（新增必须声明替换了哪条，净行数 ≤ 0，不留变更日志）· **R3** 双门检查（改完跑 `preset_check.ps1`）。

## 许可

MIT，见 [LICENSE](LICENSE)。Copyright (c) 2026 liuyun847
