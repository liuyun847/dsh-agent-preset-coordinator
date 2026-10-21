<#
.SYNOPSIS
    重算本预设与上游 shipped `standard` 的差异，供 presets/coordinator.patch.yml 头部的"当前基线"声明复核。

.DESCRIPTION
    两份 patch 文件各提取 `config.plugins` 的正文（剥离声明行包装与公共缩进），
    剔除注释行与空行后按多重集比对，输出新增/删除行数与两侧本体行数。
    同时列出全部候选 standard patch 的路径、行数与 SHA256 —— 一台机器上可能有多份 dsh 安装，
    拿旧副本对比会得出错误结论（例如把 present 行误判成本预设新增的差异）。
    因此脚本默认只用第一个存在的候选路径，并把全部候选都列出来供人工确认；
    **候选有几份、实际存在几份由输出当场呈现（Test-Path 逐个判定），文档里不写死份数**。

.NOTES
    依赖 pwsh / PowerShell 7。不改任何文件，只读。
    退出码：0 = 比对完成（有无差异都算成功）；1 = 基线文件缺失。
#>
[CmdletBinding()]
param(
    # 允许临时指定另一份基线做对照（例如升级 dsh 后核对新发布的 standard）
    [string]$Baseline,
    # 本组合包的 patch 文件，默认脚本所在目录的上一级 presets\coordinator.patch.yml
    [string]$Preset
)

$ErrorActionPreference = 'Stop'

$packDir = Split-Path -Parent $PSScriptRoot
if (-not $Preset) { $Preset = Join-Path $packDir 'presets\coordinator.patch.yml' }

# 候选基线（都是 web-app bundle 的 standard 声明 patch）：
#   · profile-link  —— profile 回退链接（~\.dsh\profiles\node_modules），指向当前活安装树；
#   · install-tree  —— 安装树直连（%APPDATA%\npm\node_modules\@deepseek-ai\dsh\node_modules）；
#   · profile-local —— profile 本地拷贝（若 profile 自行装了该 bundle）。
$baselineCandidates = @(
    [pscustomobject]@{ Label = 'profile-link'; Path = "$env:USERPROFILE\.dsh\profiles\node_modules\@deepseek-ai\dsh-web-app\presets\standard.patch.yml" },
    [pscustomobject]@{ Label = 'install-tree'; Path = "$env:APPDATA\npm\node_modules\@deepseek-ai\dsh\node_modules\@deepseek-ai\dsh-web-app\presets\standard.patch.yml" },
    [pscustomobject]@{ Label = 'profile-local'; Path = "$env:USERPROFILE\.dsh\profiles\web\node_modules\@deepseek-ai\dsh-web-app\presets\standard.patch.yml" }
)

if ($Baseline) {
    $basePath = $Baseline
    $baseLabel = '指定'
} else {
    $base = $baselineCandidates | Where-Object { Test-Path $_.Path } | Select-Object -First 1
    if (-not $base) { Write-Error "找不到 shipped standard 基线 patch；已尝试：`n$($baselineCandidates.Path -join "`n")"; exit 1 }
    $basePath = $base.Path
    $baseLabel = $base.Label
}

if (-not (Test-Path $Preset)) { Write-Error "找不到预设 patch 文件：$Preset"; exit 1 }

# 提取 `plugins:` 子列表的原始行：从 plugins 行往下，取缩进更深（或空）的行，
# 遇到缩进 ≤ plugins 行的非空行即停（不假设 plugins 是最后一个键）。
function Get-PluginsRawLines([string]$Path) {
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $idx = -1
    $baseIndent = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], '^(\s*)plugins:\s*$')
        if ($m.Success) { $idx = $i; $baseIndent = $m.Groups[1].Value.Length; break }
    }
    if ($idx -lt 0) { return @() }
    $body = New-Object System.Collections.Generic.List[string]
    for ($j = $idx + 1; $j -lt $lines.Count; $j++) {
        $ln = $lines[$j]
        if ($ln.Trim() -eq '') { continue }
        $cur = ([regex]::Match($ln, '^(\s*)')).Groups[1].Value.Length
        if ($cur -le $baseIndent) { break }
        $body.Add($ln)
    }
    return $body
}

# 剥离公共缩进 → 剔除整行注释（YAML 里的 !!js 表达式不含 '#'，整行注释判定是安全的）
# → 块标量（`|` / `>` 及其修饰符）的内容行按"内容基准缩进"归一化。
#
# 为什么需要块标量归一化：两边的块内容缩进风格可以不同（本包沿用旧文件的 +6 风格，
# 官方 patch 是 +2 风格），而 YAML 解析出的文本完全相同。不归一化会把纯风格差异
# 算进"新增/删除行"，污染基线数字（2026-09-24 迁移时实测 +12 行噪音）。
# 口径与旧版一致：剔除空行与整行注释，输出"逻辑行"。
function Get-BodyLines([string[]]$RawLines) {
    $nonEmpty = @($RawLines | Where-Object { $_.Trim() -ne '' })
    if ($nonEmpty.Count -eq 0) { return @() }
    $min = ($nonEmpty |
        ForEach-Object { ([regex]::Match($_, '^(\s*)')).Groups[1].Value.Length } |
        Measure-Object -Minimum).Minimum
    $stripped = @($nonEmpty |
        Where-Object { -not $_.TrimStart().StartsWith('#') } |
        ForEach-Object { $_.Substring($min) })

    $out = New-Object System.Collections.Generic.List[string]
    $headIndent = -1     # 当前块标量头行的缩进
    $contentIndent = -1  # 当前块标量的内容基准缩进（-2 = 等待第一行内容确定）
    foreach ($ln in $stripped) {
        if ($ln.Trim() -eq '') { $out.Add(''); continue }
        $cur = ([regex]::Match($ln, '^(\s*)')).Groups[1].Value.Length
        if ($contentIndent -ne -1) {
            if ($cur -le $headIndent) {
                $contentIndent = -1   # 块结束，本行按普通行处理
            } else {
                if ($contentIndent -eq -2) { $contentIndent = $cur }
                if ($cur -ge $contentIndent) {
                    $out.Add($ln.Substring($contentIndent))
                    continue
                }
            }
        }
        $out.Add($ln)
        if ($ln -match ':\s*[|>][+-]?\s*$') { $headIndent = $cur; $contentIndent = -2 }
    }
    return $out
}

$baseLines = Get-BodyLines (Get-PluginsRawLines $basePath)
$presetLines = Get-BodyLines (Get-PluginsRawLines $Preset)

$diff = Compare-Object -ReferenceObject $baseLines -DifferenceObject $presetLines
$removed = @($diff | Where-Object SideIndicator -eq '<=').Count
$added = @($diff | Where-Object SideIndicator -eq '=>').Count

Write-Output "预设 : $Preset"
Write-Output "基线 : [$baseLabel] $basePath"
Write-Output ''
Write-Output ("本体行数（剔除注释与空行）：{0} → {1}" -f $baseLines.Count, $presetLines.Count)
Write-Output ("差异                    ：+{0} / -{1}" -f $added, $removed)
Write-Output ''
$existingCount = @($baselineCandidates | Where-Object { Test-Path $_.Path }).Count
Write-Output ("standard 副本状态（候选 {0} 份，实际存在 {1} 份；确认没有拿旧副本对比）：" -f $baselineCandidates.Count, $existingCount)
foreach ($c in $baselineCandidates) {
    if (Test-Path $c.Path) {
        $hash = (Get-FileHash -LiteralPath $c.Path -Algorithm SHA256).Hash
        $n = (Get-Content -LiteralPath $c.Path).Count
        Write-Output ("  [{0,-13}] {1,4} 行  {2}  {3}" -f $c.Label, $n, $hash.Substring(0, 16), $c.Path)
    } else {
        Write-Output ("  [{0,-13}] 不存在  {1}" -f $c.Label, $c.Path)
    }
}

exit 0
