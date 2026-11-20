<#
.SYNOPSIS
  卸载 devin-chinese-thinking 规则。

.DESCRIPTION
  只移除本项目管理的内容，绝不删除用户自己的规则：
  - 对于本项目创建的独立规则文件（如 ~/.devin/rules/chinese-thinking.md）：
    若文件中只有本项目内容则整个删除；若混入用户内容则只移除标记块。
  - 对于追加了标记块的文件（AGENTS.md / global_rules.md）：只移除
    <!-- devin-chinese-thinking:v2 --> ... <!-- /devin-chinese-thinking:v2 -->
    之间的内容，其余原样保留。
  - -Restore：从最近的 .bak-<时间戳> 备份恢复文件（仅限被本项目修改过的文件）。
  - 默认执行前会列出将要处理的文件并要求确认；-Force 跳过确认。
  - 不需要管理员权限；不执行任何远程脚本。

.PARAMETER Restore
  从备份恢复而不是精确移除标记块。

.PARAMETER Force
  跳过交互确认。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File uninstall.ps1
  powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Restore
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Restore,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$MARKER_BEGIN = '<!-- devin-chinese-thinking:v2 -->'
$MARKER_END   = '<!-- /devin-chinese-thinking:v2 -->'
$RULE_FILE_NAME = 'chinese-thinking.md'

function Write-Info($msg) { Write-Host "[uninstall] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[uninstall] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[uninstall] $msg" -ForegroundColor Yellow }

function Get-Utf8NoBom { New-Object System.Text.UTF8Encoding($false) }

# 候选目标：与 install.ps1 对应
$targets = @(
    (Join-Path $env:USERPROFILE '.devin\rules\chinese-thinking.md'),
    (Join-Path $env:APPDATA 'devin\AGENTS.md'),
    (Join-Path $env:USERPROFILE '.devin\global_rules.md'),
    (Join-Path $env:USERPROFILE '.codeium\windsurf\memories\global_rules.md'),
    (Join-Path (Get-Location) '.devin\rules\chinese-thinking.md')
)

$plan = @()
foreach ($p in $targets) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $text = [System.IO.File]::ReadAllText($p, (Get-Utf8NoBom))
    $isOurRuleFile = ($p -like "*$RULE_FILE_NAME")
    $hasBlock = $text -match [regex]::Escape($MARKER_BEGIN)
    $hasV1Only = (-not $hasBlock) -and ($text -match 'chinese-thinking|devin-chinese-thinking')
    if ($isOurRuleFile -or $hasBlock -or $hasV1Only) {
        $plan += [pscustomobject]@{Path=$p; IsRuleFile=$isOurRuleFile; HasBlock=$hasBlock; HasV1Hint=$hasV1Only}
    }
}

if ($plan.Count -eq 0) {
    Write-Ok '未发现本项目管理的规则，无需卸载。'
    exit 0
}

Write-Host '===== 将要处理的文件 =====' -ForegroundColor White
$plan | Format-Table -AutoSize | Out-String | Write-Host

if (-not $Force) {
    $answer = Read-Host '确认卸载？输入 yes 继续'
    if ($answer -ne 'yes') { Write-Info '已取消。'; exit 0 }
}

foreach ($item in $plan) {
    $p = $item.Path
    if ($Restore) {
        $baks = Get-ChildItem -LiteralPath (Split-Path -Parent $p) -Filter "$(Split-Path -Leaf $p).bak-*" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending
        if ($baks) {
            Copy-Item -LiteralPath $baks[0].FullName -Destination $p -Force
            Write-Ok "已从备份恢复: $p  <-  $($baks[0].Name)"
        } else {
            Write-Warn2 "未找到备份，跳过恢复: $p"
        }
        continue
    }

    $text = [System.IO.File]::ReadAllText($p, (Get-Utf8NoBom))

    if ($item.IsRuleFile) {
        # 独立规则文件：仅当含本项目签名（marker 或项目名）时才删除，
        # 避免误删用户自建的同名文件
        $isOurs = ($text -match [regex]::Escape($MARKER_BEGIN)) -or
                  ($text -match 'devin-chinese-thinking')
        if (-not $isOurs) {
            Write-Warn2 "同名文件但无本项目签名，为安全起见未删除，请人工确认: $p"
            continue
        }
        if ($PSCmdlet.ShouldProcess($p, 'delete project rule file')) {
            Remove-Item -LiteralPath $p -Force
            Write-Ok "已删除规则文件: $p"
        }
        continue
    }

    if ($text -match [regex]::Escape($MARKER_BEGIN)) {
        $newText = [regex]::Replace($text,
            "(?s)\s*" + [regex]::Escape($MARKER_BEGIN) + ".*?" + [regex]::Escape($MARKER_END) + "\s*",
            "`n")
        if ($PSCmdlet.ShouldProcess($p, 'remove managed block')) {
            [System.IO.File]::WriteAllText($p, $newText, (Get-Utf8NoBom))
            Write-Ok "已移除标记块（其余内容保留）: $p"
        }
        continue
    }

    Write-Warn2 "检测到疑似 v1 手工配置但无标记块，为安全起见未自动删除，请人工处理: $p"
}

Write-Host ''
Write-Ok '卸载完成。如需回滚到安装前状态，可运行: uninstall.ps1 -Restore'
