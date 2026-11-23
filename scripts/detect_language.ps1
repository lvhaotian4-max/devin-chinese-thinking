<#
.SYNOPSIS
  检测 Devin 可见文本的汉化程度（中文 vs 英文占比）。

.DESCRIPTION
  边界声明（重要）：
  - 只能分析你**显式提供**的可见文本（从 Devin 界面复制出的
    思考说明、计划、回复等保存为 .txt）。
  - 无法读取模型隐藏的内部推理；本脚本不声称检测"思维链内部语言"，
    只统计"可见文本的自然语言段落中英文分布"。
  - 优先调用 tests\check_drift.py（Python）；无 Python 时用内置
    PowerShell 统计做近似判断。

  判定（drift_ratio = 英文段 / 有效段）：
    < 0.1  → 中文为主，汉化生效
    0.1~0.3 → 偶发漂移，建议新开会话或装 hook
    > 0.3  → 漂移明显，检查规则是否加载（status.ps1）

.PARAMETER TextFile
  包含可见文本的 .txt 文件路径（必填其一，或用 -Text 直接传字符串）。

.PARAMETER Text
  直接传入文本字符串（适合短文本）。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File detect_language.ps1 -TextFile visible.txt
  powershell -ExecutionPolicy Bypass -File detect_language.ps1 -Text "I will check the files."
#>
[CmdletBinding()]
param(
    [string]$TextFile,
    [string]$Text
)

$ErrorActionPreference = 'Stop'
# 统一控制台输出为 UTF-8，避免中文乱码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { if (-not [Console]::IsOutputRedirected) { chcp 65001 | Out-Null } } catch {}
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$driftPy = Join-Path $repoRoot 'tests\check_drift.py'

function Get-Utf8NoBom { New-Object System.Text.UTF8Encoding($false) }

Write-Host '===== 可见文本汉化检测 =====' -ForegroundColor White
Write-Host '注意：只统计你提供的可见文本样本，不代表模型隐藏推理。' -ForegroundColor DarkGray
Write-Host ''

# ---- 取文本 ----
$raw = $null
$source = ''
if ($TextFile) {
    if (-not (Test-Path -LiteralPath $TextFile)) { Write-Host "[x] 文件不存在: $TextFile" -ForegroundColor Red; exit 2 }
    $raw = [System.IO.File]::ReadAllText($TextFile, (Get-Utf8NoBom))
    $source = $TextFile
} elseif ($Text) {
    $raw = $Text
    $source = '<inline>'
} else {
    Write-Host '用法: detect_language.ps1 -TextFile <file> 或 -Text "<text>"' -ForegroundColor Yellow
    exit 2
}

# ---- 优先用 check_drift.py ----
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python -and (Test-Path -LiteralPath $driftPy)) {
    $tmp = Join-Path $env:TEMP ("dct-detect-" + $PID + ".txt")
    [System.IO.File]::WriteAllText($tmp, $raw, (Get-Utf8NoBom))
    try {
        $json = & python $driftPy $tmp 2>$null | Out-String
        $report = $json | ConvertFrom-Json
        $ratio = [double]$report.drift_ratio
        $verdict = if ($ratio -lt 0.1) { '中文为主（汉化生效）' }
                   elseif ($ratio -le 0.3) { '偶发漂移（建议新开会话或装 hook）' }
                   else { '漂移明显（检查规则是否加载）' }
        $color = if ($ratio -lt 0.1) {'Green'} elseif ($ratio -le 0.3) {'Yellow'} else {'Red'}
        Write-Host "来源: $source" -ForegroundColor White
        Write-Host "有效段落: $($report.total_segments)  中文:$($report.zh_segments)  英文:$($report.en_segments)  混合:$($report.mixed_segments)  忽略:$($report.ignored_segments)"
        Write-Host "drift_ratio: $ratio  →  $verdict" -ForegroundColor $color
        if ($report.flagged) {
            Write-Host '' -ForegroundColor White
            Write-Host '英文样例（前 5 条）:' -ForegroundColor Yellow
            $report.en_samples | Select-Object -First 5 | ForEach-Object { Write-Host "  - $($_.Substring(0, [Math]::Min(120, $_.Length)))" -ForegroundColor DarkGray }
        }
        exit 0
    } catch {
        Write-Host "[!] check_drift.py 调用失败，改用内置统计: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host '[i] 未找到 python/check_drift.py，使用内置近似统计。' -ForegroundColor DarkGray
}

# ---- 内置近似统计 ----
$segments = $raw -split "`n"
$zh = 0; $en = 0
$cjk = [regex]'[一-鿿]'
$latin = [regex]'[A-Za-z]'
foreach ($seg in $segments) {
    $s = $seg.Trim()
    if ($s.Length -lt 10) { continue }
    if ($cjk.IsMatch($s)) { $zh++ }
    elseif (($latin.Matches($s)).Count -ge 4) { $en++ }
}
$total = $zh + $en
$ratio = if ($total -gt 0) { [math]::Round($en / $total, 3) } else { 0 }
$verdict = if ($ratio -lt 0.1) { '中文为主（汉化生效）' }
           elseif ($ratio -le 0.3) { '偶发漂移（建议新开会话或装 hook）' }
           else { '漂移明显（检查规则是否加载）' }
$color = if ($ratio -lt 0.1) {'Green'} elseif ($ratio -le 0.3) {'Yellow'} else {'Red'}
Write-Host "来源: $source（内置近似统计，未剔除代码/日志）"
Write-Host "中文段:$zh  英文段:$en  drift_ratio≈$ratio  →  $verdict" -ForegroundColor $color
exit 0
