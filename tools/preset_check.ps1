<#
.SYNOPSIS
    预设与项目文档的防膨胀双门检查（R3）：预算门 + 重复门。

.DESCRIPTION
    规格见 README「防膨胀设计」一节。
    两个门：

      1. 预算门（硬门，超限 exit 1）
         逐文件比对 行数 / 字节数 与硬编码上限，超标项逐条列出。
         口径（与 preset_diff.ps1 的「本体行数」完全不同，勿互相误读）：
           行数   = (Get-Content -LiteralPath <f> -Encoding UTF8).Count   —— 全部行，含空行与注释
           字节数 = [System.IO.File]::ReadAllBytes(<f>).Length            —— 无换行符歧义，跨平台一致

      2. 重复门（只警告，**不影响退出码**）
         按「连续非空行」切段，仅 **≥ 4 行** 的段落参与比对：归一化（每行 Trim → 去行首注释符
         '#' 及其后空白 → 以 LF 重连）后取 MD5，同一哈希在同一文件**或跨文件**出现 ≥ 2 次即报。
         只用**精确哈希**，不做语义相似度——宁可漏报不可误报。

    比对范围：预算门覆盖的 4 份文件，加上不计预算门的长文档 SKILL.md。

.NOTES
    只读脚本：绝不写入/修改/删除任何文件，只调用 Get-Content / ReadAllBytes 级别的读操作。
    依赖：pwsh 7 与 Windows PowerShell 5.1 均可运行（不使用 ?? / ?. / ForEach-Object -Parallel 等 7.x 专有语法）。
    退出码：0 = 两门通过；1 = 预算门失败；2 = 目标文件缺失（或 -Root 目录不存在）。

    2026-09-25：内存载体 `context.md`（项目根 .dsh\.project\ 下的文件）退役，改由进程内任务板工具承担，
    故比对源不再包含任何**包外**文件——`-Workspace` 参数随之删除：它唯一的用途就是定位那个文件，
    包外比对需求消失即不留空参数（将来若真要查包外文件，再按需加参，而不是写死一个默认路径）。

    预算口径中**来自用户决议**的例外（**不是漏写，勿事后补上**，依据见 README「防膨胀设计」）：
      · 上限只保留给**「每轮注入」**的文件（天花板来自注入成本，与「文档该多长」无关）——
        不得因为下面的 skip 就顺手把它的上限也取消。
      · 按需加载的长文档**不设上限**（硬顶只会逼人删内容），靠 R0「完成即移出」与重复门治理：
        不计预算门、输出行仍显示实测行数/字节数、状态列标「(no budget — by decision)」，
        但**仍参与重复门**——它们的唯一闸门是 R0 的移出率，不是行数。
      · 汇总行的「checked N files」只计预算门覆盖的文件（不含上面几份）。
#>
[CmdletBinding()]
param(
    # 组合包目录。默认 = 本脚本所在目录的上一级（即 dsh-agent-preset-coordinator\）
    [string]$Root,
    # 只输出错误行与最后汇总行
    [switch]$Quiet
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# 中文输出在两个宿主下的编码基线（必须在任何输出之前）：
# Windows PowerShell 5.1 的控制台默认编码是当前 ANSI 代码页，直接输出中文会乱码；
# 统一钉成 UTF-8（无 BOM），使 5.1 与 pwsh 7 的输出一致。
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $utf8NoBom
    $OutputEncoding = $utf8NoBom
} catch { }

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

# ---------------------------------------------------------------- 预算表（硬编码天花板）
# 值取自 README「防膨胀设计」的预算口径；改此处即为改预算，须同时改那边。
# 这里只收录**每轮注入**的文件：上限来自注入成本，不是「文档该多长」。
$budgets = [ordered]@{
    'presets\coordinator.patch.yml'            = @{ Lines = 420; Bytes = 32000 }
    'presets\executor.patch.yml'               = @{ Lines = 130; Bytes = 7500 }
    'skills\project-coordination\BASELINE.md'  = @{ Lines = 300; Bytes = 15000 }
    'skills\project-coordination\DECISIONS.md' = @{ Lines = 300; Bytes = 15000 }
}

# 不计预算门、只受重复门约束的**按需加载长文档**（依据：README「防膨胀设计」）
#   SKILL.md 行数与字节都不设上限，按「按需查阅文档」处理。
# 与预算门文件同等对待：仍显示实测行数/字节数，状态列统一标注 (no budget — by decision)，仍参与重复门。
# 全部相对 Root（组合包目录）解析：内存载体已改为进程内任务板工具，不再有包外的比对源。
$noBudget = @(
    'skills\project-coordination\SKILL.md'
)

# 重复门参数
$minBlockLines = 4      # 只有 ≥ 4 行的连续非空行段落才参与比对
$snippetLen    = 40     # 输出每个段落的前 N 字（列宽，CJK 按 2 列）

# ---------------------------------------------------------------- 小工具
$script:useColor = $true
try { if ([Console]::IsOutputRedirected) { $script:useColor = $false } } catch { $script:useColor = $false }

function Write-Line([string]$Text, [string]$Color) {
    if ($script:useColor -and $Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}

# 显示宽度（CJK 等宽字符按 2 列计），用于对齐中英混排的表格
function Get-DisplayWidth([string]$Text) {
    $w = 0
    foreach ($ch in $Text.ToCharArray()) {
        if ([int]$ch -ge 0x1100) { $w += 2 } else { $w += 1 }
    }
    return $w
}

# 按「显示宽度」而不是 UTF-16 码元数补空格：
# PowerShell 的 PadLeft/PadRight 只数码元，中英混排的表格会歪（CJK 占 2 列却只算 1 个码元）。
function Format-Cell([string]$Text, [int]$Width, [string]$Align) {
    $pad = $Width - (Get-DisplayWidth $Text)
    if ($pad -lt 0) { $pad = 0 }
    if ($Align -eq 'Right') { return ((' ' * $pad) + $Text) }
    return ($Text + (' ' * $pad))
}

function Get-Snippet([string]$Text, [int]$MaxCols) {
    $sb = New-Object System.Text.StringBuilder
    $w = 0
    foreach ($ch in $Text.ToCharArray()) {
        $cw = 1
        if ([int]$ch -ge 0x1100) { $cw = 2 }
        if (($w + $cw) -gt $MaxCols) { break }
        [void]$sb.Append($ch)
        $w += $cw
    }
    $s = $sb.ToString()
    if ($s.Length -lt $Text.Length) { return $s + '...' }
    return $s
}

# 段落归一化：去每行首尾空白 → 去行首注释符 '#' 及其后空白 → 行尾统一 LF
function Get-NormalizedBlock([string]$Raw) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($ln in ($Raw -split "`n")) {
        $t = $ln.Trim()
        while ($t.StartsWith('#')) { $t = $t.Substring(1).TrimStart() }
        $out.Add($t)
    }
    return ($out -join "`n")
}

function Get-Hash([string]$Text) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $md5.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '')
    } finally {
        $md5.Dispose()
    }
}

# 把「行数组」按连续非空行切段，只返回长度 ≥ MinLen 的段
function Get-Blocks([string[]]$Lines, [int]$MinLen) {
    $blocks = New-Object System.Collections.Generic.List[object]
    $i = 0
    $n = $Lines.Count
    while ($i -lt $n) {
        if ($Lines[$i].Trim() -eq '') { $i++; continue }
        $start = $i
        while ($i -lt $n -and $Lines[$i].Trim() -ne '') { $i++ }
        $len = $i - $start
        if ($len -ge $MinLen) {
            $blocks.Add(@{
                StartLine = $start + 1
                Length    = $len
                Text      = ($Lines[$start..($i - 1)] -join "`n")
            })
        }
    }
    return $blocks
}

# ---------------------------------------------------------------- 头部
# 列宽按显示宽度（列）计，不是字符数
$colFile  = 44
$colLines = 11
$colBytes = 14

if (-not $Quiet) {
    Write-Line 'preset_check: 防膨胀检查（只读）'
    Write-Line ("Root      : {0}" -f $Root)
    Write-Line '口径      : 行数 = Get-Content 全部行（含空行与注释）；字节数 = ReadAllBytes().Length'
    Write-Line ''
    Write-Line (('{0}  {1}  {2}  {3}' -f (Format-Cell '文件' $colFile 'Left'), (Format-Cell '行数/上限' $colLines 'Right'), (Format-Cell '字节/上限' $colBytes 'Right'), '状态'))
    Write-Line (('{0}  {1}  {2}  {3}' -f ('-' * $colFile), ('-' * $colLines), ('-' * $colBytes), ('-' * 20)))
}

# ---------------------------------------------------------------- 预算门
$rows      = New-Object System.Collections.Generic.List[object]
$missing   = New-Object System.Collections.Generic.List[string]
$overItems = New-Object System.Collections.Generic.List[object]
$checked   = 0
$rootMissing = -not (Test-Path -LiteralPath $Root -PathType Container)

foreach ($rel in $budgets.Keys) {
    $full = Join-Path $Root $rel
    if ($rootMissing -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
        $missing.Add($rel)
        $rows.Add([pscustomobject]@{ Name = $rel; LineCell = '-'; ByteCell = '-'; Status = '缺失' })
        continue
    }
    $checked++
    $lineCount = (Get-Content -LiteralPath $full -Encoding UTF8).Count
    $byteCount = [System.IO.File]::ReadAllBytes($full).Length
    $lim = $budgets[$rel]
    $overL = $lineCount - $lim.Lines
    $overB = $byteCount - $lim.Bytes
    if ($overL -gt 0 -or $overB -gt 0) {
        $status = 'OVER'
        $overItems.Add([pscustomobject]@{
            Name = $rel; Lines = $lineCount; LineLimit = $lim.Lines; OverLines = $overL
            Bytes = $byteCount; ByteLimit = $lim.Bytes; OverBytes = $overB
        })
    } else {
        $status = 'OK'
    }
    $rows.Add([pscustomobject]@{
        Name     = $rel
        LineCell = ("{0}/{1}" -f $lineCount, $lim.Lines)
        ByteCell = ("{0}/{1}" -f $byteCount, $lim.Bytes)
        Status   = $status
    })
}

# 不计预算门、但受重复门约束的文件（按需查阅文档）
# 路径先行解析好，重复门（含 -Quiet 分支）与显示共用同一份，避免两处口径漂移。
$noBudgetFiles = New-Object System.Collections.Generic.List[object]
foreach ($rel in $noBudget) {
    $noBudgetFiles.Add([pscustomobject]@{ Rel = $rel; Full = (Join-Path $Root $rel) })
}

if (-not $Quiet) {
    foreach ($nb in $noBudgetFiles) {
        if (Test-Path -LiteralPath $nb.Full -PathType Leaf) {
            $nbLines = (Get-Content -LiteralPath $nb.Full -Encoding UTF8).Count
            $nbBytes = [System.IO.File]::ReadAllBytes($nb.Full).Length
            $rows.Add([pscustomobject]@{
                Name     = $nb.Rel
                LineCell = ("{0}" -f $nbLines)
                ByteCell = ("{0}" -f $nbBytes)
                Status   = '(no budget — by decision)'
            })
        } else {
            $rows.Add([pscustomobject]@{
                Name = $nb.Rel; LineCell = '-'; ByteCell = '-'
                Status = '缺失（仅重复门；缺失不 fail）'
            })
        }
    }

    foreach ($r in $rows) {
        $statusColor = $null
        if ($r.Status -eq 'OVER') { $statusColor = 'Red' }
        elseif ($r.Status -eq '缺失') { $statusColor = 'Red' }
        elseif ($r.Status -like '(no budget*') { $statusColor = 'Yellow' }
        $line = ('{0}  {1}  {2}  {3}' -f (Format-Cell $r.Name $colFile 'Left'), (Format-Cell $r.LineCell $colLines 'Right'), (Format-Cell $r.ByteCell $colBytes 'Right'), $r.Status)
        Write-Line $line $statusColor
    }
    Write-Line ''
}

# 缺失文件（目标文件缺失 → exit 2，与超预算区分开）
if ($rootMissing) {
    Write-Line ("错误: -Root 目录不存在 - {0}" -f $Root) 'Red'
}
foreach ($m in $missing) {
    Write-Line ("错误: 目标文件缺失 - {0}" -f (Join-Path $Root $m)) 'Red'
}
if ($missing.Count -gt 0) {
    Write-Line ("预算门: FAIL（{0} 个目标文件缺失）" -f $missing.Count) 'Red'
    Write-Line ''
}

# 超预算明细
if ($overItems.Count -gt 0) {
    Write-Line '超预算明细（文件 · 实测 · 预算 · 超出量）:' 'Red'
    foreach ($o in $overItems) {
        if ($o.OverLines -gt 0) {
            Write-Line ("  {0} · 行数 {1} · 预算 {2} · 超出 {3}" -f $o.Name, $o.Lines, $o.LineLimit, $o.OverLines) 'Red'
        }
        if ($o.OverBytes -gt 0) {
            Write-Line ("  {0} · 字节 {1} · 预算 {2} · 超出 {3}" -f $o.Name, $o.Bytes, $o.ByteLimit, $o.OverBytes) 'Red'
        }
    }
    Write-Line ''
}

# ---------------------------------------------------------------- 重复门（只警告，不影响退出码）
$allBlocks = New-Object System.Collections.Generic.List[object]
$sources = New-Object System.Collections.Generic.List[object]
foreach ($rel in $budgets.Keys) {
    $sources.Add([pscustomobject]@{ Rel = $rel; Full = (Join-Path $Root $rel) })
}
# 不计预算门的文件同样进重复门：SKILL.md 也在比对源集合里
foreach ($nb in $noBudgetFiles) {
    $sources.Add([pscustomobject]@{ Rel = $nb.Rel; Full = $nb.Full })
}

foreach ($src in $sources) {
    if (-not (Test-Path -LiteralPath $src.Full -PathType Leaf)) { continue }
    $lines = @(Get-Content -LiteralPath $src.Full -Encoding UTF8)
    foreach ($b in (Get-Blocks $lines $minBlockLines)) {
        $norm = Get-NormalizedBlock $b.Text
        $allBlocks.Add([pscustomobject]@{
            File      = $src.Rel
            StartLine = $b.StartLine
            Length    = $b.Length
            Hash      = (Get-Hash $norm)
            Snippet   = (Get-Snippet (($b.Text -split "`n")[0].Trim()) $snippetLen)
        })
    }
}

# 按哈希分组，取出现 ≥ 2 次的组
$groups = @{}
foreach ($b in $allBlocks) {
    if (-not $groups.ContainsKey($b.Hash)) { $groups[$b.Hash] = New-Object System.Collections.Generic.List[object] }
    $groups[$b.Hash].Add($b)
}

$dupGroups = New-Object System.Collections.Generic.List[object]
foreach ($key in $groups.Keys) {
    $g = $groups[$key]
    if ($g.Count -ge 2) {
        $sorted = @($g | Sort-Object -Property @{ Expression = { $_.File }; Descending = $false }, @{ Expression = { $_.StartLine }; Descending = $false })
        $rep = $sorted[0]
        $dupGroups.Add([pscustomobject]@{
            Files     = (($sorted | ForEach-Object { "{0}:{1}" -f $_.File, $_.StartLine }) -join ' | ')
            Snippet   = $rep.Snippet
            LineCount = $rep.Length
            Count     = $sorted.Count
        })
    }
}
$dups = @($dupGroups | Sort-Object -Property Snippet, Files)

$dupCount = 0
foreach ($d in $dups) { $dupCount += ($d.Count - 1) }

if (-not $Quiet) {
    if ($dups.Count -eq 0) {
        Write-Line '重复门: 无疑似重复段'
    } else {
        Write-Line ("重复门: {0} 组疑似重复段（只警告，不影响退出码）:" -f $dups.Count) 'Yellow'
        foreach ($d in $dups) {
            Write-Line ("  {0}  [{1} 行 x{2}]  {3}" -f $d.Files, $d.LineCount, $d.Count, $d.Snippet) 'Yellow'
        }
    }
    Write-Line ''
}

# ---------------------------------------------------------------- 汇总与退出码
$budgetVerdict = 'PASS'
if ($missing.Count -gt 0) { $budgetVerdict = 'ERROR' }
elseif ($overItems.Count -gt 0) { $budgetVerdict = 'FAIL' }

if (-not $Quiet) { Write-Line ("预算门: {0}" -f $budgetVerdict) $(if ($budgetVerdict -eq 'PASS') { 'Green' } else { 'Red' }) }
Write-Line ("汇总: checked {0} files, {1} over budget, {2} duplicate candidates" -f $checked, $overItems.Count, $dupCount)

if ($missing.Count -gt 0) { exit 2 }
if ($overItems.Count -gt 0) { exit 1 }
exit 0
