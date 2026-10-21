#!/usr/bin/env python3
"""预设组合（bundle patch 声明行）与锚点的校验（只读）。

两部分检查：

1. **YAML 语法与结构**。patch 文件里含 `!!js` 自定义标签（如
   `disabled: !!js process.platform === 'win32'`），标准 YAML 解析器会以
   "could not determine a constructor for the tag" 拒绝，必须先注册构造器再解析 ——
   否则会把"合法文件"误判成语法错误。结构检查：顶层恰一项 insert，其中一行
   `@deepseek-ai/dsh-agent-preset` 声明（config.id / config.name / config.plugins）。
2. **命名锚点**（仅整目录模式）。锚点存在的唯一理由是替代会静默漂移的行号引用，
   所以悬空引用、无人引用的死锚点、以及行号引用的回归都必须响亮失败。

用法:  uv run --with pyyaml tools/validate_yaml.py [路径...]
       省略路径时校验 presets/ 下的两份组合文件，并附加锚点交叉校验。

退出码: 0 = 全部通过；1 = 至少一项检查失败；2 = 缺少 PyYAML。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# 输出编码兜底（与 tools/preset_check.ps1 的约定对齐：那里把 [Console]::OutputEncoding 钉成 UTF-8）。
#
# 动机：本脚本会**回显源文件的行内容**，而文档里有 GBK 无码位的字符（`✓`、`✔`、`─` 之类）。
# 在 zh-CN 的 cmd/PowerShell 里跑，一旦 stdout/stderr 被重定向进管道，Python 取的是 **locale
# ANSI 码页**（gbk）而不是控制台码页 —— 所以 `chcp 65001` 无效，`python -X utf8` 或
# `PYTHONIOENCODING=utf-8` 才有效。命中的那一行含不可编码字符时，print 会抛 UnicodeEncodeError
# **直接中断**，后面几条 FAIL 与最后的汇总行全部丢失（最坏情况：报错看起来像"脚本坏了"，
# 实际是"检查没跑完"）。这里显式重配为 UTF-8 + errors="backslashreplace"：宁可把不可编码
# 字符写成 `\u2713`，也不能让检查半路断掉。任何控制台/管道组合下都不再因编码中断。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="backslashreplace")
    except (AttributeError, ValueError):
        # AttributeError：流被换成了没有 reconfigure 的对象（如某些 IDE/测试夹具的包装流）；
        # ValueError：流已关闭或已分离。两者都只意味着"兜底不可用"，不该让脚本起不来。
        pass

try:
    import yaml
except ImportError:  # pragma: no cover - 环境缺失时的明确提示
    print("缺少 PyYAML：uv run --with pyyaml tools/validate_yaml.py", file=sys.stderr)
    raise SystemExit(2)


class JsExpression(str):
    """`!!js` 表达式占位：只占位，不求值（本脚本不模拟 Loader 的运行环境）。"""


def _js_constructor(loader: yaml.Loader, node: yaml.Node) -> JsExpression:
    if isinstance(node, yaml.ScalarNode):
        return JsExpression(loader.construct_scalar(node))
    if isinstance(node, yaml.SequenceNode):
        return JsExpression(str(loader.construct_sequence(node)))
    return JsExpression(str(loader.construct_mapping(node)))


def _count(rows: list) -> tuple[int, int, int]:
    """返回 (全部行, 组容器行, 插件行)。

    组行（`group: true`）自身只提供 isolate realm 与嵌套容器，不注册任何插件 ——
    所以"插件行"才是与运行期 `compositionInventory()` 可对照的数字。
    """
    total = groups = 0
    for row in rows:
        total += 1
        if row.get("group"):
            groups += 1
        nested = row.get("config")
        if isinstance(nested, list):
            sub_total, sub_groups, _ = _count(nested)
            total += sub_total
            groups += sub_groups
    return total, groups, total - groups


def _validate_plugin_rows(path: Path, plugins: list, prefix: str = "") -> bool:
    """校验一行插件列表（递归前先查 id/name），失败打印并返回 False。"""
    bad = [r for r in plugins if not isinstance(r, dict) or "id" not in r or "name" not in r]
    if bad:
        print(f"FAIL  {path.name}\n      {prefix}{len(bad)} 个条目缺少 id 或 name")
        return False
    return True


def validate_patch(path: Path, doc: list) -> bool:
    """校验 bundle patch 形态：一项 insert（含 preset 声明行）+ 可选 id 覆盖行。"""
    inserts = [r for r in doc if isinstance(r, dict) and "insert" in r]
    if len(inserts) != 1:
        print(f"FAIL  {path.name}\n      insert 项应为 1 个（得到 {len(inserts)}）")
        return False
    insert = inserts[0]["insert"]
    if not isinstance(insert, list) or not insert:
        print(f"FAIL  {path.name}\n      insert 不是非空列表（得到 {type(insert).__name__}）")
        return False
    decl = None
    for row in insert:
        if isinstance(row, dict) and row.get("name") == "@deepseek-ai/dsh-agent-preset":
            decl = row
            break
    if decl is None:
        print(f"FAIL  {path.name}\n      insert 里没有 @deepseek-ai/dsh-agent-preset 声明行")
        return False
    cfg = decl.get("config")
    if not isinstance(cfg, dict):
        print(f"FAIL  {path.name}\n      声明行缺少 config 映射")
        return False
    for key in ("id", "plugins"):
        if key not in cfg:
            print(f"FAIL  {path.name}\n      声明 config 缺少必填键 {key!r}")
            return False
    plugins = cfg["plugins"]
    if not isinstance(plugins, list) or not plugins:
        print(f"FAIL  {path.name}\n      config.plugins 不是非空列表")
        return False
    if not _validate_plugin_rows(path, plugins):
        return False

    # id 覆盖行（无 insert）：按 id 覆写上游行的字段，如 registry 的默认预设覆盖。
    overrides = [r for r in doc if isinstance(r, dict) and "insert" not in r]
    for row in overrides:
        if not isinstance(row.get("id"), str) or row["id"] == "":
            print(f"FAIL  {path.name}\n      覆盖行缺少非空 id：{row!r}")
            return False
        if "config" in row and not isinstance(row["config"], dict):
            print(f"FAIL  {path.name}\n      覆盖行 {row['id']!r} 的 config 不是映射")
            return False

    enabled = sum(1 for r in plugins if not r.get("disabled"))
    group_rows = [r for r in plugins if r.get("group")]
    total, groups, plugin_rows = _count(plugins)
    override_note = "" if not overrides else f"；覆盖行 {len(overrides)} 条({', '.join(r['id'] for r in overrides)})"
    print(
        f"OK    {path.name}: 声明 id={cfg['id']!r} name={cfg.get('name')!r} order={cfg.get('order')}；"
        f"全部 {total} 行 = 插件行 {plugin_rows} + 组容器 {groups}"
        f"{[g['id'] for g in group_rows]}；顶层启用 {enabled} / 禁用 {len(plugins) - enabled}{override_note}"
    )
    return True


def validate(path: Path) -> bool:
    """解析一个文件并打印结构摘要；返回是否通过。

    两类形态：
      · bundle patch —— 顶层序列，恰一项 insert，含 preset 声明行（现行形态）；
      · 通用序列     —— 顶层序列，每项含 id / name（旧 agent.cordis.yml 形态，保留兼容）。
    """
    yaml.SafeLoader.add_constructor("tag:yaml.org,2002:js", _js_constructor)
    yaml.SafeLoader.add_constructor("!js", _js_constructor)
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        mark = getattr(exc, "problem_mark", None)
        where = f"（行 {mark.line + 1}, 列 {mark.column + 1}）" if mark else ""
        print(f"FAIL  {path.name} {where}\n      {exc}")
        return False

    # 元数据映射（旧 preset.yml 形态，保留兼容）
    if isinstance(doc, dict):
        unknown = set(doc) - {"name", "description", "order"}
        if "name" not in doc:
            print(f"FAIL  {path.name}\n      缺少 name")
            return False
        note = f"，未知键 {sorted(unknown)}（检查是否拼错）" if unknown else ""
        print(f"OK    {path.name}: 元数据（name={doc['name']!r}，order={doc.get('order')}）{note}")
        return True

    if not isinstance(doc, list):
        print(f"FAIL  {path.name}\n      顶层既不是序列也不是映射（得到 {type(doc).__name__}）")
        return False

    # bundle patch 形态：至少一项 insert（可附带 id 覆盖行，如 registry 的默认预设覆盖）
    if any(isinstance(r, dict) and "insert" in r for r in doc):
        return validate_patch(path, doc)

    # 通用序列形态
    if not _validate_plugin_rows(path, doc):
        return False
    enabled = sum(1 for r in doc if not r.get("disabled"))
    group_rows = [r for r in doc if r.get("group")]
    total, groups, plugins = _count(doc)
    print(
        f"OK    {path.name}: 全部 {total} 行 = 插件行 {plugins} + 组容器 {groups}"
        f"{[g['id'] for g in group_rows]}；顶层启用 {enabled} / 禁用 {len(doc) - enabled}"
    )
    return True


def check_anchors(root: Path) -> bool:
    """校验命名锚点，并禁止退回行号引用。

    锚点存在的唯一理由，是替代会静默漂移的行号引用（见 BASELINE.md 第一节）。因此
    引用写错名字、锚点块被删、或有人图省事又把行号写回去，都必须**响亮失败**。
    只做名字级校验；锚点块的具体位置由真实挂载校验兜底。
    """
    compositions = [root / "presets" / name for name in ("coordinator.patch.yml", "executor.patch.yml")]
    missing = [path for path in compositions if not path.exists()]
    if missing:
        print(f"FAIL  锚点校验：找不到 {', '.join(str(path) for path in missing)}")
        return False

    anchor_re = re.compile(r"\[anchor:\s*([a-z0-9-]+)\s*\]")
    defined = set()
    for composition in compositions:
        defined |= set(anchor_re.findall(composition.read_text(encoding="utf-8")))
    if not defined:
        print("FAIL  锚点校验：组合文件里没有任何 [anchor:...] 定义（引用会指向空气）")
        return False

    # 引用面：本预设内除组合文件自身以外的全部 markdown。定义行在组合文件里，
    # 因此任何来自其它文件的命中都是"外部引用"，不需要排除自己。
    sources = sorted(set(root.glob("skills/**/*.md")) | set(root.glob("*.md")))
    referenced: dict[str, set[str]] = {}
    line_hits: list[str] = []
    # 行号引用回归检测。
    #
    # 为什么不能只判"附近性"（本判据上一版的做法）：标点写法确实很多，但**只要求"文件名与
    # 其后 20 字符内的数字同时出现"必然过宽** —— 本仓库的文档里满是**体积/行数统计**
    # （文档里的体积/行数统计表：`…\agent.cordis.yml` | 389 / 24181 → 373 / 23030）、
    # 时间戳备份文件名（`agent.cordis.yml.bak-20260911`）、以及"两文件行数均不变（…= 373）"
    # 这类计数句。它们与行号引用共享同一批文件名和数字，于是本文档自己的统计表全被打成 FAIL：
    # 一个**永远红的检查等于没有检查**（迟早被人绕过、注释掉或删掉，那才是真的失去防护）。
    #
    # 因此判据收紧为：**文件名之后 20 字符内必须出现"行号语义标记"**，标记只有三类：
    #   · 冒号引用：文件名后紧跟 `:` / `：` 再接数字 —— `coordinator.patch.yml:307-311`、
    #     隔一个反引号的 `` `coordinator.patch.yml`:307 ``，以及窗口内出现的 `` `:307-311` ``；
    #   · 序数引用：`第` + 数字 + `行`（数字可带区间）—— `coordinator.patch.yml 第 20–35 行`；
    #   · 区间引用：数字区间后紧跟 `行` —— `coordinator.patch.yml 的 307-311 行`。
    #   · 豁免：`.bak` 时间戳备份文件名（`.bak` 紧随其后即跳过）；上游源码的 `文件:行号`
    #     引用（文件名不在本仓库文件名集合内）；一切**计数句** —— `= 373 行`、`| 389 | 340 |`、
    #     `389 / 24181 → 373 / 23030`、`新增第 4 条` 都不带上述标记。
    # 已知盲区（**宁可漏报不误报**，同 preset_check.ps1 重复门的取舍）：单个数字 + `行` 且既无
    # 「第」也无冒号（如 `yml 的 307 行`）与"共 373 行"这类计数句在局部特征上无法区分，故不判命中；
    # `第 20–35 行` 这种省掉扩展名的写法也抓不到。真把行号写回来时，冒号式与区间式仍会 FAIL。
    own_names = re.compile(r"(agent\.cordis\.yml|coordinator\.patch\.yml|SKILL\.md|DECISIONS\.md|BASELINE\.md)")
    colon_ref = re.compile(r"^\s*`?\s*[:：]\s*\d{1,4}|`\s*[:：]\s*\d{1,4}")
    ordinal_ref = re.compile(r"第\s*\d{1,4}\s*(?:[-\u2013\u2014~]\s*\d{1,4})?\s*行")
    range_ref = re.compile(r"\d{1,4}\s*[-\u2013\u2014~]\s*\d{1,4}\s*行")

    def has_line_ref(window: str) -> bool:
        """窗口内是否出现"行号语义标记"（判据见上方注释）。"""
        return bool(colon_ref.search(window) or ordinal_ref.search(window) or range_ref.search(window))

    for source in sources:
        for lineno, line in enumerate(source.read_text(encoding="utf-8").splitlines(), start=1):
            for name in anchor_re.findall(line):
                referenced.setdefault(name, set()).add(source.name)
            if anchor_re.search(line):
                continue  # 这一行已经用了锚点，不追究
            hit = False
            for name_match in own_names.finditer(line):
                if line[name_match.end() :].startswith(".bak"):
                    continue  # 时间戳备份文件名，不是引用
                if has_line_ref(line[name_match.end() : name_match.end() + 20]):
                    hit = True
                    break
            if hit:
                line_hits.append(f"{source.name}:{lineno}  {line.strip()[:80]}")
    # 不做静默截断：这些都是失败项，只报前 10 条会让第 11 条以后永远不可见

    dangling = sorted(set(referenced) - defined)
    unused = sorted(defined - set(referenced))
    ok = True
    for name in dangling:
        ok = False
        print(f"FAIL  悬空锚点 [{name}]：被 {', '.join(sorted(referenced[name]))} 引用，但组合文件里没有定义")
    for name in unused:
        ok = False
        print(f"FAIL  锚点 [{name}] 已定义但无人引用（引用方大概改回了行号）")
    for hit in line_hits:
        ok = False
        print(f"FAIL  行号引用回归：{hit}（请改回 [anchor: <名字>]）")
    if ok:
        print(f"OK    锚点: {len(defined)} 个定义、{len(referenced)} 个被引用，名称全部对得上 {sorted(defined)}；无行号引用回归")
    return ok


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parent.parent
    if argv:
        targets = [Path(a) for a in argv]
    else:
        targets = [root / "presets" / name for name in ("executor.patch.yml", "coordinator.patch.yml")]
    ok = True
    for target in targets:
        if not target.exists():
            print(f"FAIL  {target} 不存在")
            ok = False
            continue
        ok = validate(target) and ok
    # 只在默认（整目录）模式下做锚点交叉校验；显式指定单个文件时不做
    if not argv:
        ok = check_anchors(root) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
