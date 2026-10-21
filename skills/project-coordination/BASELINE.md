# 与上游 `standard` 的对照（历史档案）

> 本文件是**历史档案**，不是操作手册：`presets/coordinator.patch.yml` 改行时人工查阅，模型不需要读它。
> 它也不被技能扫描器读取——扫描器只认技能根下第一层的 `<名字>/SKILL.md` 或 `<名字>.md`
> （`dsh-skill-filesystem/lib/index.js:548-556`），与 `DECISIONS.md` 同级放在
> `skills/project-coordination/` 下因此是安全的。
>
> **唯一权威**：`presets/coordinator.patch.yml` 内联注释里那条不能违反的约束（全仓库唯一副本），
> 锚点 [`subagent-preset`]。本文件只记录"改了什么、为什么"，不复述该约束。

## 一、基线与重算

| 项 | 值 |
|---|---|
| 基线 | shipped `standard` @ `dsh-web-app` bundle **0.1.7-rc.1**（`presets/standard.patch.yml`） |
| 基线路径 | `%USERPROFILE%\.dsh\profiles\node_modules\@deepseek-ai\dsh-web-app\presets\standard.patch.yml` |
| 重算差异 | `pwsh tools/preset_diff.ps1` |
| 语法校验 | `uv run --with pyyaml tools/validate_yaml.py` |

**本机存在两份 `standard`，逐字节相同**（脚本每次都会把全部候选连哈希一起列出）：

| 标签 | 版本 | 行数 | SHA256（前 16 位） |
|---|---|---|---|
| `profile-link`（宿主实际加载） | 0.1.7-rc.1 | 146 | `6CD2F197737FC94A` |
| `install-tree`（与 profile-link 逐字节相同） | 0.1.7-rc.1 | 146 | `6CD2F197737FC94A` |
| `profile-local` | 不存在 | — | — |

> 上表"行数"是 **patch 文件全行数**（含头部注释与声明行包装）；`preset_diff.ps1` 打印的
> "本体行数"是 `config.plugins` 正文剔除注释与空行后的**逻辑行数**（见第二节），两个口径别混读。
>
> 2026-09-24 迁移前的旧基线是目录组合 `dsh-agent-presets\presets\standard\agent.cordis.yml`
> （0.1.5-rc.1 时 255 行 / `08A029C64FDEAABE`）；`dsh-agent-presets` 包已随 0.1.7-rc.1 移除，
> 历史记录里的 "old-copy 0.1.2-alpha.3"（257 行 / `F04FBC6EC6D38AAB`）与"三份副本"口径
> 随之作废——**那个坑（拿旧副本对比会把 `present` 行误判成本预设新增）已不再存在**。

**`present` 行不是差异。** `@deepseek-ai/dsh-tool-present` 在 0.1.5-rc.1 的 standard 里同样存在，
两侧逐行一致；登记在此只是免去下次对比时的重复排查（这个坑已经踩过一次）。

## 二、与基线的差异清单

剔除注释与空行后按多重集比对：**基线 131 行 → 本预设 172 行，新增 59 / 删除 18**。
下面数字的单位统一是"行"，与条目数分开计；数字由 `tools/preset_diff.ps1` 当场重算，
块标量（`|` 块）内容按"内容基准缩进"归一化后再比，纯缩进风格差异不计入。

| 改动 | 行数 | 说明 |
|---|---|---|
| persona `prefix` 块 | **+34 / −1** | 协调者铁律（数值随人格演进，精确重算见 `tools/preset_diff.ps1`） |
| 两个委派工具行的 config | **+21 / −1** | `toolFilter` + `deny` 块 8 行（`toolFilter:` / `deny:` / 两个工具名，各 2 行）、`persona` 键与人格正文 13 行（spawn 6 + fork 7）、删除上游"子代理按任务选模型"的开关 1 行 |
| `skill-filesystem` 的 config | **+3** | `config:` / `customSkillDirs:` / `!!js` 表达式（0.1.7 起官方写法：`createRequire(baseUrl)` 解析包目录） |
| plan-mode `section` | **+1 / −1** | 同行改写：`explicit assumptions` 明确为"未验证事实 + 各自验证方式" |
| 移除 workflow 两条 | **−6** | `workflow-ptc`（id/name/config/provider）4 行 + `tool-workflow`（id/name）2 行 |
| 移除 `tool-ralph` | **−6** | id/name/disabled/config/subagentProvider/maxRounds 共 6 行 |
| 未跟 `tool-plugin-manager` | **−3** | 0.1.7 的 standard 新增该行（`disabled: true`）；生产协调者不需要创造模式的 plugin_manager 工具 |

⚠ `persona` 是**新增键**，基线两个委派工具行的 config 里根本没有它——不能记成"行内取值变化"。

各处合计正好 +59 / −18，未被覆盖的内容与基线一致。逐条保留/移除的决策依据见 `DECISIONS.md`。

> **基线随 dsh 升级而变**：0.1.6 → 0.1.7 的 standard 有两处演进——工作流行由
> `workflow-worker-thread` 改名 `workflow-ptc`、新增 `tool-plugin-manager` 行（默认禁用）。
> 下次升级后重跑 `preset_diff.ps1`，差异构成若变，先分辨"上游改了什么"再改本表。

## 三、被移除的条目

### `workflow`（`workflow-worker-thread` + `tool-workflow`）

前台阻塞调用（"the parent turn blocks until the whole workflow settles — there is no
background start/poll API"），与铁律一直接冲突；它还注册一条常驻 prompt 段劝导模型使用它，
和人格对打。扇出改由"一条消息里并发多次 `subagent` 调用"承担，同样非阻塞。
`delegation` 组的 `isolate` 域为它保留着，取消 `presets/coordinator.patch.yml` 里两条的注释即可恢复。

### `tool-ralph`

首要理由同样是**前台阻塞**：ralph 是 "a fixed foreground loop"，调用
"blocks until the whole run settles"（`dsh-tool-ralph/README.md:12,28,32`）。它一轮跑一个
全新子代理，**默认上限 256 轮**（README:43）—— 协调者一旦调用就可能被卡住数小时，比 workflow
更严重。

次要理由：每轮起全新代理、以工作区为长期记忆，语义与 `continuable` + goal 重叠；其规范自身
也要求"仅在人类明确要求 Ralph 式迭代时使用"，自动协调场景不会合规触发。

恢复：取消 `presets/coordinator.patch.yml` 里注释掉的 `tool-ralph` 行（`maxRounds: 64`）。
**只能由人类明确点名使用，不要主动调。** 包在 0.1.7-rc.1 下仍随宿主出货（standard 里也有该行，默认 `disabled: true`）。

## 四、两条已排除的路线（实测记录）

### 不要挂 `@deepseek-ai/dsh-tool-subagent-report`

该包依赖 `ctx.subagents.registerContinuableSetup`，而 0.1.5-rc.1 的 `subagents` 服务已无此方法。
实测挂载失败：

```
ctx.subagents.registerContinuableSetup is not a function
```

也没有升级路径：npm 上该包最新发布版就是本机这份 0.1.2-alpha.3，从未跟进 0.1.5 的服务接口，
属于废弃包。**等上游重发之前，回报一律走 `send_message`。**

子 → 父的回报通道**不需要额外插件**：`dsh-tool-subagent-control` 提供的 `send_message` 是双向的
（父 → 直接子代理，常驻 continuable 子代理 → 其直接父代理），子代理结束时还有服务自带的结算
通知送达父代理。闭环已经完整。

### 没有"会话级租约"闸门，也不打算加

结构层的会话级租约闸门曾评估过、2026-09-12 决定不做，且它第一版本来也不覆盖文件冲突。
独占资源（电脑控制 / 前台键鼠 / Godot 运行时）与共享 cwd 的并发纪律因此**只能靠协调者
串行派活**，不要指望将来会有这个闸门兜住。完整边界见 `SKILL.md` 的「六、并发与成本的真实边界」。

## 五、工具面隔离的真实边界（实测确认）

子代理默认通过 `agentPresets.composeFrom()` 加入父代理**同一个 standing 组合**（0.2.1 起可用 `agentPreset` 指定另一份预设，那时它加入的是那份预设的组合）：

> "a bind, not a mount ... the same plugin objects, the same tool
> registrations, the same prompt sections."

也就是说协调者与子代理共享同一套工具注册，**无法用增删 plugin 行**把 shell 或写工具
"只留给子代理"。实测：子代理默认继承父代理全部工具（工具数随会话加载的 MCP / 插件浮动，
本机量级为近百个，**别把具体数字当常量**）。

例外只有两类，都已在本预设里用上：

- **人格可以隔离** —— 0.2.1 起不再有 `persona` 字段：改由独立 Agent 预设承担，spawn 行用 `agentPreset: executor` 指过去，子代理因此不再继承协调者的铁律；不给它换人格，最坏结果是静默空转（把任务再转包一层然后回复"已派活"）。
- **委派工具可以结构隔离** —— 同样落在那个独立预设里：`executor` 的插件列表**根本不含**委派行，子代理手上就没有 `subagent` / `subagent_fork`（工具仍留在协调者手上）。fork 后端拿不到独立预设（`inheritsParentContext`），只能靠 `maxDepth: 1` 限制它继续派活。

其余工具面依旧无法隔离：禁掉 `tool-pwsh`，子代理就再也跑不了构建和测试。因此
"协调者只委派不执行"**只能由 persona 纪律保证**。
