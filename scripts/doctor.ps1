<#
.SYNOPSIS
  检查 devin-chinese-thinking 规则的安装状态、冲突与加载指引。

.DESCRIPTION
  只读检查，不修改任何文件。检查项：
  - 各候选规则路径是否存在、是否包含本项目标记
  - 文件编码（应为 UTF-8 无 BOM）与 frontmatter
  - 新旧规则并存等冲突提示
  - 输出人工验证加载的步骤指引

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File doctor.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$MARKER = '<!-- devin-chinese-thinking:v2 -->'
$MARKER_V1_HINT = 'chinese-thinking'

function Get-Utf8NoBom { New-Object System.Text.UTF8Encoding($false) }

$checks = @()

function Add-Check([string]$Name, [string]$Path, [string]$Detail) {
    $script:checks += [pscustomobject]@{Item=$Name; Path=$Path; Status=$Detail}
}

function Inspect-File([string]$Name, [string]$Path, [bool]$ExpectFrontmatter) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Check $Name $Path 'MISSING'
        return
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.IO.File]::ReadAllText($Path, (Get-Utf8NoBom))
    $hasMarker = $text -match [regex]::Escape($MARKER)
    $hasLangRule = $text -match 'thinking|思考链|内部推理|reasoning'
    $status = @()
    $status += "exists"
    $status += $(if ($hasBom) { 'UTF8-BOM!' } else { 'utf8-nobom' })
    $status += $(if ($hasMarker) { 'managed-by-project' } else { 'user-content' })
    $status += $(if ($hasLangRule) { 'lang-rule-found' } else { 'no-lang-rule' })
    if ($ExpectFrontmatter) {
        $status += $(if ($text -match '(?s)\A---.*?trigger:\s*always_on.*?---') { 'frontmatter-ok' } else { 'frontmatter-missing' })
    }
    Add-Check $Name $Path ($status -join ', ')
}

Write-Host '===== devin-chinese-thinking doctor =====' -ForegroundColor White
Write-Host "时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "用户: $env:USERNAME   APPDATA: $env:APPDATA"
Write-Host ''

# 新版 Devin 路径
Inspect-File 'devin rules (user)' (Join-Path $env:USERPROFILE '.devin\rules\chinese-thinking.md') $true
Inspect-File 'devin global AGENTS.md' (Join-Path $env:APPDATA 'devin\AGENTS.md') $false
Inspect-File 'devin global rules.md' (Join-Path $env:USERPROFILE '.devin\global_rules.md') $false
Inspect-File 'project .devin/rules' (Join-Path (Get-Location) '.devin\rules\chinese-thinking.md') $true

# 旧版兼容路径
Inspect-File 'legacy windsurf global_rules' (Join-Path $env:USERPROFILE '.codeium\windsurf\memories\global_rules.md') $false
Inspect-File 'legacy windsurf rules dir' (Join-Path (Get-Location) '.windsurf\rules') $false

# 其他可能的全局规则
Inspect-File 'devin AGENT.md (alt)' (Join-Path $env:APPDATA 'devin\AGENT.md') $false
Inspect-File 'claude CLAUDE.md' (Join-Path $env:USERPROFILE '.claude\CLAUDE.md') $false

Write-Host ''
Write-Host '===== 检查结果 =====' -ForegroundColor White
$checks | Format-Table -AutoSize | Out-String | Write-Host

# 冲突分析
$managed = @($checks | Where-Object { $_.Status -match 'managed-by-project' })
$unmanaged = @($checks | Where-Object { $_.Status -match 'user-content' -and $_.Status -match 'lang-rule-found' })
Write-Host '===== 分析 =====' -ForegroundColor White
if ($managed.Count -eq 0 -and $unmanaged.Count -eq 0) {
    Write-Host '[!] 未检测到本项目规则，也未检测到任何语言规则。请运行 install.ps1。' -ForegroundColor Yellow
} else {
    if ($managed.Count -gt 0) { Write-Host "[OK] 已安装本项目规则: $($managed.Count) 处" -ForegroundColor Green }
    if ($unmanaged.Count -gt 0) {
        Write-Host "[i] 检测到非本项目管理的语言类规则 $($unmanaged.Count) 处（可能是旧版 v1 手工配置或其他来源）:" -ForegroundColor Yellow
        $unmanaged | ForEach-Object { Write-Host "    - $($_.Path)" }
        Write-Host '    建议：确认内容无冲突后可保留；uninstall.ps1 只会移除带本项目标记的内容。' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '===== 人工验证加载（Devin 无法从脚本侧确认注入结果） =====' -ForegroundColor White
Write-Host '1. 完全退出并重启 Devin Desktop，或新开一个会话。'
Write-Host '2. 发送任务，例如: "列出当前目录文件"。'
Write-Host '3. 观察可见的思考说明/计划/工具调用说明是否为简体中文。'
Write-Host '4. 如需验证子代理：让 Agent 执行一个会派生 subagent 的任务（如"全面搜索 xxx 的用法"）。'
Write-Host '5. 如需验证项目级规则：在项目根目录放 .devin\rules\ 后重开该项目会话。'
Write-Host ''
Write-Host '提示：本工具只检查文件状态；规则是否真正被模型遵循，需要人工观察输出。' -ForegroundColor DarkGray
