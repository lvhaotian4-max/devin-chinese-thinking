<#
.SYNOPSIS
  安装 devin-chinese-thinking 语言规则（v2，always_on）。

.DESCRIPTION
  - 默认安装到用户级 Devin 规则目录 %USERPROFILE%\.devin\rules\
  - 同时可选兼容旧版路径：%APPDATA%\devin\AGENTS.md 与
    %USERPROFILE%\.codeium\windsurf\memories\global_rules.md
    （仅追加带标记的规则块，绝不覆盖已有内容）
  - -IncludeHooks：额外安装生命周期 hook（SessionStart +
    UserPromptSubmit），每次会话/每次提问重新注入语言指令，
    是抗长上下文漂移的最强手段；会备份并合并 config.json
  - 幂等：重复运行不会产生重复规则；已安装则报告"已是最新/已存在"
  - 自动备份：修改任何已有文件前，先复制到 <file>.bak-<时间戳>
  - 不需要管理员权限；不执行任何远程脚本；不修改 Devin 程序本体

.PARAMETER Scope
  user     = 全局用户级（默认）
  project  = 当前目录 .devin\rules\（项目级）

.PARAMETER Targets
  devin    = 仅新版 Devin 路径（默认）
  legacy   = 仅旧版 Windsurf/Cascade 兼容路径
  all      = 新版 + 旧版都装（推荐双保险）

.PARAMETER IncludeHooks
  同时安装中文语言 hook（需要本机有 node）。不安装则行为与旧版一致。

.PARAMETER WhatIfOnly
  只打印将要执行的操作，不写入任何文件。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -Targets all
  powershell -ExecutionPolicy Bypass -File install.ps1 -Targets all -IncludeHooks
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('user','project')]
    [string]$Scope = 'user',
    [ValidateSet('devin','legacy','all')]
    [string]$Targets = 'devin',
    [switch]$IncludeHooks,
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'
$MARKER_BEGIN = '<!-- devin-chinese-thinking:v2 -->'
$MARKER_END   = '<!-- /devin-chinese-thinking:v2 -->'
$RULE_FILE_NAME = 'chinese-thinking.md'
$HOOK_FILE_NAME = 'devin-chinese-thinking.mjs'

function Write-Info($msg) { Write-Host "[install] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[install] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[install] $msg" -ForegroundColor Yellow }
function Write-Err2($msg) { Write-Host "[install] $msg" -ForegroundColor Red }

function Get-Utf8NoBom {
    return New-Object System.Text.UTF8Encoding($false)
}

function Backup-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = "$Path.bak-$stamp"
    Copy-Item -LiteralPath $Path -Destination $bak -Force
    Write-Info "已备份: $bak"
    return $bak
}

function Write-Utf8File([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (Get-Utf8NoBom))
}

# 读取仓库内模板正文（安装脚本所在目录的上一级 templates\）
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$templatePath = Join-Path $repoRoot 'templates\chinese-thinking-v2.md'
if (-not (Test-Path -LiteralPath $templatePath)) {
    Write-Err2 "找不到模板文件: $templatePath"
    Write-Err2 "请确认 install.ps1 位于仓库 scripts\ 目录下。"
    exit 1
}
$template = [System.IO.File]::ReadAllText($templatePath, (Get-Utf8NoBom))

# 从模板中剥离 frontmatter，得到可追加到 AGENTS.md 的正文块
$body = $template -replace '(?s)\A---.*?---\s*', ''
# 追加块由外层 MARKER 包裹，剔除模板内的签名注释避免嵌套标记
$body = $body -replace '(?m)^\s*<!-- devin-chinese-thinking:v2 -->\s*\r?\n?', ''
$appendBlock = @"

$MARKER_BEGIN
$body
$MARKER_END
"@

$results = @()

function Install-RuleFile([string]$Path, [string]$Content, [string]$Label) {
    if (Test-Path -LiteralPath $Path) {
        $existing = [System.IO.File]::ReadAllText($Path, (Get-Utf8NoBom))
        if ($existing -match [regex]::Escape($MARKER_BEGIN)) {
            Write-Ok "$Label`: 已安装（检测到标记），跳过。路径: $Path"
            $script:results += [pscustomobject]@{Target=$Label; Path=$Path; Action='skipped-already-installed'}
            return
        }
        # 已存在但非本项目管理：不覆盖，写入冲突报告
        Write-Warn2 "$Label`: 文件已存在且非本项目管理，为避免破坏用户规则，未写入。请手动合并: $Path"
        $script:results += [pscustomobject]@{Target=$Label; Path=$Path; Action='conflict-manual-merge'}
        return
    }
    if ($WhatIfOnly) {
        Write-Info "[WhatIf] 将创建 $Label`: $Path"
        $script:results += [pscustomobject]@{Target=$Label; Path=$Path; Action='would-create'}
        return
    }
    Write-Utf8File -Path $Path -Content $Content
    Write-Ok "$Label`: 已创建 $Path"
    $script:results += [pscustomobject]@{Target=$Label; Path=$Path; Action='created'}
}

function Install-AppendBlock([string]$Path, [string]$Block, [string]$Label) {
    $exists = Test-Path -LiteralPath $Path
    $existing = ''
    if ($exists) { $existing = [System.IO.File]::ReadAllText($Path, (Get-Utf8NoBom)) }

    if ($existing -match [regex]::Escape($MARKER_BEGIN)) {
        # 幂等更新：替换旧块
        if ($WhatIfOnly) {
            Write-Info "[WhatIf] 将更新 $Label` 中的规则块: $Path"
            $script:results += [pscustomobject]@{Target=$Label; Path=$Path; Action='would-update'}
            return
        }
        Backup-File -Path $Path | Out-Null
        $newContent = [regex]::Replace($existing,
            "(?s)" + [regex]::Escape($MARKER_BEGIN) + ".*?" + [regex]::Escape($MARKER_END),
            $Block.Trim())
        Write-Utf8File -Path $Path -Content $newContent
        Write-Ok "$Label`: 已更新规则块 $Path"
        $script:results += [pscustomobject]@{Target=$Label; Path=$Path; Action='updated'}
        return
    }

    if ($WhatIfOnly) {
        Write-Info "[WhatIf] 将向 $Label` 追加规则块: $Path"
        $script:results += [pscustomobject]@{Target=$Label; Path=$Path; Action='would-append'}
        return
    }
    if ($exists) { Backup-File -Path $Path | Out-Null }
    $newContent = if ([string]::IsNullOrWhiteSpace($existing)) { $Block.TrimStart() } else { $existing.TrimEnd() + $Block }
    Write-Utf8File -Path $Path -Content $newContent
    Write-Ok "$Label`: 已追加规则块 $Path"
    $script:results += [pscustomobject]@{Target=$Label; Path=$Path; Action='appended'}
}

# ---------- 可选：生命周期 hook（抗漂移最强手段） ----------
function Install-Hooks {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Warn2 '未检测到 node，跳过 hook 安装（规则文件不受影响）。'
        $script:results += [pscustomobject]@{Target='hooks'; Path=''; Action='skipped-no-node'}
        return
    }

    $configDir = Join-Path $env:APPDATA 'devin'
    $configPath = Join-Path $configDir 'config.json'
    $hooksDir = Join-Path $configDir 'hooks'
    $hookPath = Join-Path $hooksDir $HOOK_FILE_NAME
    $hookTemplate = Join-Path $repoRoot 'assets\hooks\devin-chinese-thinking.mjs'

    if (-not (Test-Path -LiteralPath $hookTemplate)) {
        Write-Warn2 "找不到 hook 模板: $hookTemplate，跳过。"
        return
    }

    # 1) 若 config.json 已存在任何引用 chinese-thinking 的 hook 命令，视为已由
    #    用户/旧版配置覆盖，避免重复注入
    if (Test-Path -LiteralPath $configPath) {
        $cfgText = [System.IO.File]::ReadAllText($configPath, (Get-Utf8NoBom))
        if ($cfgText -match 'chinese-thinking[^"\\]*\.mjs') {
            Write-Ok "hooks: 已检测到现有 chinese-thinking hook 配置，跳过（避免重复注入）。"
            $script:results += [pscustomobject]@{Target='hooks'; Path=$configPath; Action='skipped-existing-hook'}
            return
        }
    }

    if ($WhatIfOnly) {
        Write-Info "[WhatIf] 将安装 hook 文件 $hookPath 并合并 $configPath"
        $script:results += [pscustomobject]@{Target='hooks'; Path=$configPath; Action='would-install'}
        return
    }

    # 2) 安装 hook 脚本（UTF-8 无 BOM）
    $hookContent = [System.IO.File]::ReadAllText($hookTemplate, (Get-Utf8NoBom))
    Write-Utf8File -Path $hookPath -Content $hookContent
    Write-Ok "hooks: 已安装 $hookPath"

    # 3) 合并进 config.json（先备份；保留其他所有键）
    $cfg = $null
    if (Test-Path -LiteralPath $configPath) {
        Backup-File -Path $configPath | Out-Null
        try {
            $cfg = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Err2 "config.json 解析失败，为安全起见未修改。请手动检查: $configPath"
            $script:results += [pscustomobject]@{Target='hooks'; Path=$configPath; Action='error-config-parse'}
            return
        }
    } else {
        $cfg = [pscustomobject]@{}
    }

    $hookCommand = "node `"$hookPath`""
    $events = @('SessionStart','UserPromptSubmit')
    if (-not ($cfg.PSObject.Properties['hooks'])) {
        $cfg | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([pscustomobject]@{})
    }
    foreach ($ev in $events) {
        $arr = @()
        if ($cfg.hooks.PSObject.Properties[$ev] -and $cfg.hooks.$ev) {
            $arr = @($cfg.hooks.$ev)
        }
        # 检查是否已有等价条目（同一命令）
        $exists = $false
        foreach ($entry in $arr) {
            foreach ($h in @($entry.hooks)) {
                if ($h.command -and $h.command -match 'chinese-thinking') { $exists = $true }
            }
        }
        if ($exists) { continue }
        $newEntry = [pscustomobject]@{
            matcher = ''
            hooks   = @([pscustomobject]@{ type='command'; command=$hookCommand; timeout=5 })
        }
        $arr += $newEntry
        $cfg.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue $arr -Force
    }

    $json = $cfg | ConvertTo-Json -Depth 10
    Write-Utf8File -Path $configPath -Content ($json + "`n")
    Write-Ok "hooks: 已合并到 $configPath（SessionStart + UserPromptSubmit）"
    $script:results += [pscustomobject]@{Target='hooks'; Path=$configPath; Action='installed'}
}

if ($Scope -eq 'project') {
    $rulePath = Join-Path (Get-Location) '.devin\rules\chinese-thinking.md'
    Install-RuleFile -Path $rulePath -Content $template -Label 'project .devin/rules'
} else {
    if ($Targets -in @('devin','all')) {
        # 新版 Devin：用户级 rules 目录（官方文档支持 ~/.devin/rules/*.md）
        $devinRule = Join-Path $env:USERPROFILE '.devin\rules\chinese-thinking.md'
        Install-RuleFile -Path $devinRule -Content $template -Label 'user ~/.devin/rules'

        # 新版 Devin：全局 AGENTS.md（追加标记块，不覆盖）
        $agentsPath = Join-Path $env:APPDATA 'devin\AGENTS.md'
        Install-AppendBlock -Path $agentsPath -Block $appendBlock -Label 'user %APPDATA%/devin/AGENTS.md'
    }
    if ($Targets -in @('legacy','all')) {
        # 旧版 Windsurf/Cascade 兼容：codeium 记忆规则（追加标记块）
        $windsurfPath = Join-Path $env:USERPROFILE '.codeium\windsurf\memories\global_rules.md'
        Install-AppendBlock -Path $windsurfPath -Block $appendBlock -Label 'legacy windsurf global_rules'
    }
    if ($IncludeHooks) { Install-Hooks }
}

Write-Host ''
Write-Host '===== 安装结果 =====' -ForegroundColor White
$results | Format-Table -AutoSize | Out-String | Write-Host

$conflicts = @($results | Where-Object { $_.Action -eq 'conflict-manual-merge' })
if ($conflicts.Count -gt 0) {
    Write-Warn2 "存在 $($conflicts.Count) 处冲突：目标文件已存在且非本项目管理。"
    Write-Warn2 "请手动把 templates\chinese-thinking-v2.md 的内容合并进去，或运行 status.ps1 查看详情。"
}
Write-Ok "完成。重启 Devin 或新开会话后生效。运行 scripts\status.ps1 可验证加载状态。"
