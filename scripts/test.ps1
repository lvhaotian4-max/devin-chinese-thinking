<#
.SYNOPSIS
  devin-chinese-thinking 自动化测试（沙箱模式，不触碰真实用户配置）。

.DESCRIPTION
  在临时目录中重定向 USERPROFILE / APPDATA，模拟全新 Windows 用户环境，
  依次运行 install.ps1 / uninstall.ps1 / status.ps1 的真实子进程，
  覆盖以下场景：

    T01 首次安装（-Targets all）
    T02 重复安装幂等（无重复标记块）
    T03 原有用户规则保留
    T04 规则更新（损坏标记块后重装可恢复）
    T05 目标文件不存在时自动创建
    T06 文件编码 UTF-8 无 BOM
    T07 中文内容正确保存
    T08 备份与 -Restore 恢复
    T09 安全卸载（只删本项目内容）
    T10 异常处理（缺模板、空环境卸载）
    T11 hooks 安装/卸载往返（需 node，缺失则 SKIP）
    T12 项目级 -Scope project 安装
    T13 冲突不覆盖（同名非本项目文件）
    T14 demo/ 离线可用（无外部资源引用）
    T15 status.ps1 只读检查可运行

  所有断言失败会汇总输出；退出码 = 失败数（0 = 全部通过）。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File test.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
# 统一控制台输出为 UTF-8，避免中文乱码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { if (-not [Console]::IsOutputRedirected) { chcp 65001 | Out-Null } } catch {}
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

# ---------- 沙箱环境 ----------
$sandbox = Join-Path $env:TEMP ("dct-test-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-" + $PID)
$userHome = Join-Path $sandbox 'userprofile'
$appData  = Join-Path $sandbox 'appdata'
$workDir  = Join-Path $sandbox 'workdir'
foreach ($d in @($userHome, $appData, $workDir, (Join-Path $sandbox 'empty-scripts'))) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

$realUserProfile = $env:USERPROFILE
$realAppData = $env:APPDATA
$realPwd = Get-Location

$env:USERPROFILE = $userHome
$env:APPDATA = $appData
Set-Location $workDir

$script:pass = 0
$script:fail = 0
$script:skip = 0
$script:results = @()

function Record([string]$Id, [string]$Name, [string]$Status, [string]$Detail) {
    $script:results += [pscustomobject]@{ID=$Id; Test=$Name; Status=$Status; Detail=$Detail}
    switch ($Status) {
        'PASS' { $script:pass++; Write-Host "  [PASS] $Id $Name" -ForegroundColor Green }
        'FAIL' { $script:fail++; Write-Host "  [FAIL] $Id $Name — $Detail" -ForegroundColor Red }
        'SKIP' { $script:skip++; Write-Host "  [SKIP] $Id $Name — $Detail" -ForegroundColor Yellow }
    }
}

function Invoke-Ps([string]$ScriptPath, [string[]]$ArgList, [string]$Cwd = $null) {
    $psi = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $ScriptPath) + $ArgList
    if ($Cwd) { Push-Location $Cwd } else { Push-Location $workDir }
    try {
        $out = & powershell @psi 2>&1 | Out-String
        return @{ Output = $out; Code = $LASTEXITCODE }
    } finally {
        Pop-Location
    }
}

function Assert-True([bool]$Cond, [string]$Detail) { if (-not $Cond) { throw $Detail } }

$installPs1 = Join-Path $scriptDir 'install.ps1'
$uninstallPs1 = Join-Path $scriptDir 'uninstall.ps1'
$statusPs1 = Join-Path $scriptDir 'status.ps1'

$agentsPath = Join-Path $appData 'devin\AGENTS.md'
$windsurfPath = Join-Path $userHome '.codeium\windsurf\memories\global_rules.md'
$devinRulePath = Join-Path $userHome '.devin\rules\chinese-thinking.md'
$configPath = Join-Path $appData 'devin\config.json'
$hookPath = Join-Path $appData 'devin\hooks\devin-chinese-thinking.mjs'

Write-Host "===== devin-chinese-thinking test.ps1 =====" -ForegroundColor White
Write-Host "沙箱: $sandbox"
Write-Host "USERPROFILE -> $userHome"
Write-Host "APPDATA     -> $appData"
Write-Host ''

# ---------- T01 首次安装 ----------
try {
    $r = Invoke-Ps $installPs1 @('-Targets','all')
    Assert-True ($r.Code -eq 0) "install exit=$($r.Code)"
    Assert-True (Test-Path -LiteralPath $devinRulePath) 'devin rule file missing'
    Assert-True (Test-Path -LiteralPath $agentsPath) 'AGENTS.md missing'
    Assert-True (Test-Path -LiteralPath $windsurfPath) 'global_rules.md missing'
    Record 'T01' '首次安装(-Targets all)' 'PASS' ''
} catch { Record 'T01' '首次安装(-Targets all)' 'FAIL' $_.Exception.Message }

# ---------- T02 重复安装幂等 ----------
try {
    $r = Invoke-Ps $installPs1 @('-Targets','all')
    Assert-True ($r.Code -eq 0) "install exit=$($r.Code)"
    foreach ($f in @($devinRulePath, $agentsPath, $windsurfPath)) {
        $t = [System.IO.File]::ReadAllText($f)
        $cnt = ([regex]::Matches($t, [regex]::Escape('<!-- devin-chinese-thinking:v2 -->'))).Count
        Assert-True ($cnt -le 1) "$f marker count=$cnt"
    }
    Record 'T02' '重复安装幂等' 'PASS' ''
} catch { Record 'T02' '重复安装幂等' 'FAIL' $_.Exception.Message }

# ---------- T03 原有用户规则保留 ----------
try {
    # 在全新沙箱2中验证：预置用户内容再安装
    $u2 = Join-Path $sandbox 'case3'; $a2 = Join-Path $sandbox 'case3-ada'
    New-Item -ItemType Directory -Path $u2,$a2 -Force | Out-Null
    $agents2 = Join-Path $a2 'devin\AGENTS.md'
    New-Item -ItemType Directory -Path (Split-Path $agents2) -Force | Out-Null
    [System.IO.File]::WriteAllText($agents2, "# 我的个人规则`n- 始终使用 tabs 缩进`n- 不要动我的笔记`n", (New-Object System.Text.UTF8Encoding($false)))
    $env:USERPROFILE = $u2; $env:APPDATA = $a2
    $r = Invoke-Ps $installPs1 @('-Targets','devin')
    $env:USERPROFILE = $userHome; $env:APPDATA = $appData
    Assert-True ($r.Code -eq 0) "install exit=$($r.Code)"
    $t = [System.IO.File]::ReadAllText($agents2)
    Assert-True ($t -match '不要动我的笔记') 'user content lost'
    Assert-True ($t -match 'devin-chinese-thinking:v2') 'managed block missing'
    # 备份应存在
    $baks = Get-ChildItem -LiteralPath (Split-Path $agents2) -Filter 'AGENTS.md.bak-*' -ErrorAction SilentlyContinue
    Assert-True ($baks.Count -ge 1) 'backup not created'
    Record 'T03' '原有用户规则保留+备份' 'PASS' ''
} catch { Record 'T03' '原有用户规则保留+备份' 'FAIL' $_.Exception.Message; $env:USERPROFILE=$userHome; $env:APPDATA=$appData }

# ---------- T04 规则更新 ----------
try {
    $t = [System.IO.File]::ReadAllText($windsurfPath)
    # 故意破坏标记块内容
    $t2 = $t -replace '(?s)(<!-- devin-chinese-thinking:v2 -->).*?(<!-- /devin-chinese-thinking:v2 -->)', "`$1`n# 旧版本内容`n`$2"
    [System.IO.File]::WriteAllText($windsurfPath, $t2, (New-Object System.Text.UTF8Encoding($false)))
    $r = Invoke-Ps $installPs1 @('-Targets','all')
    Assert-True ($r.Code -eq 0) "install exit=$($r.Code)"
    $t3 = [System.IO.File]::ReadAllText($windsurfPath)
    Assert-True ($t3 -match '防漂移约定') 'block not updated to v2 template'
    Assert-True ($t3 -notmatch '旧版本内容') 'stale content remains'
    Record 'T04' '规则更新(损坏块恢复)' 'PASS' ''
} catch { Record 'T04' '规则更新(损坏块恢复)' 'FAIL' $_.Exception.Message }

# ---------- T05 文件不存在自动创建 ----------
try {
    # T01 已在全新沙箱创建，验证内容非空且含 frontmatter
    $t = [System.IO.File]::ReadAllText($devinRulePath)
    Assert-True ($t -match '(?s)\A---.*?trigger:\s*always_on.*?---') 'frontmatter missing'
    Assert-True ($t.Length -gt 200) 'rule file too small'
    Record 'T05' '文件不存在自动创建' 'PASS' ''
} catch { Record 'T05' '文件不存在自动创建' 'FAIL' $_.Exception.Message }

# ---------- T06 编码 UTF-8 无 BOM ----------
try {
    foreach ($f in @($devinRulePath, $agentsPath, $windsurfPath)) {
        $bytes = [System.IO.File]::ReadAllBytes($f)
        Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "$f has BOM"
    }
    Record 'T06' '编码 UTF-8 无 BOM' 'PASS' ''
} catch { Record 'T06' '编码 UTF-8 无 BOM' 'FAIL' $_.Exception.Message }

# ---------- T07 中文内容保存 ----------
try {
    $t = [System.IO.File]::ReadAllText($agentsPath, (New-Object System.Text.UTF8Encoding($false)))
    Assert-True ($t -match '简体中文') 'chinese text missing'
    Assert-True ($t -match '推理') 'reasoning clause missing'
    Record 'T07' '中文内容正确保存' 'PASS' ''
} catch { Record 'T07' '中文内容正确保存' 'FAIL' $_.Exception.Message }

# ---------- T08 备份恢复 ----------
try {
    # 在 case3 沙箱（含用户原始内容+安装备份）上验证 -Restore：
    # 恢复后 AGENTS.md 应回到安装前的用户原文
    $agents3bak = Join-Path (Join-Path $sandbox 'case3-ada') 'devin\AGENTS.md'
    # 先确认当前含标记块
    $cur = [System.IO.File]::ReadAllText($agents3bak)
    Assert-True ($cur -match 'devin-chinese-thinking:v2') 'setup: managed block missing'
    $env:USERPROFILE = Join-Path $sandbox 'case3'
    $env:APPDATA = Join-Path $sandbox 'case3-ada'
    $r = Invoke-Ps $uninstallPs1 @('-Restore','-Force')
    $env:USERPROFILE = $userHome; $env:APPDATA = $appData
    Assert-True ($r.Code -eq 0) "uninstall exit=$($r.Code) : $($r.Output)"
    $after = [System.IO.File]::ReadAllText($agents3bak)
    Assert-True ($after -match '不要动我的笔记') 'restore lost user original content'
    Assert-True ($after -notmatch 'devin-chinese-thinking:v2') 'managed block still present after restore'
    Record 'T08' '备份 -Restore 恢复' 'PASS' ''
} catch { $env:USERPROFILE=$userHome; $env:APPDATA=$appData; Record 'T08' '备份 -Restore 恢复' 'FAIL' $_.Exception.Message }

# ---------- T09 安全卸载 ----------
try {
    # 确保 AGENTS.md 含用户内容+标记块
    $u3 = Join-Path $sandbox 'case9'; $a3 = Join-Path $sandbox 'case9-ada'
    New-Item -ItemType Directory -Path $u3,$a3 -Force | Out-Null
    $agents3 = Join-Path $a3 'devin\AGENTS.md'
    New-Item -ItemType Directory -Path (Split-Path $agents3) -Force | Out-Null
    [System.IO.File]::WriteAllText($agents3, "# 用户规则`n- 我的自定义条款XYZ`n", (New-Object System.Text.UTF8Encoding($false)))
    $env:USERPROFILE = $u3; $env:APPDATA = $a3
    Invoke-Ps $installPs1 @('-Targets','devin') | Out-Null
    $r = Invoke-Ps $uninstallPs1 @('-Force')
    $env:USERPROFILE = $userHome; $env:APPDATA = $appData
    Assert-True ($r.Code -eq 0) "uninstall exit=$($r.Code)"
    $t = [System.IO.File]::ReadAllText($agents3)
    Assert-True ($t -match '我的自定义条款XYZ') 'user content removed!'
    Assert-True ($t -notmatch 'devin-chinese-thinking:v2') 'managed block remains'
    # 同目录规则文件也应被删
    $rule3 = Join-Path $u3 '.devin\rules\chinese-thinking.md'
    Assert-True (-not (Test-Path -LiteralPath $rule3)) 'rule file not deleted'
    Record 'T09' '安全卸载(保留用户内容)' 'PASS' ''
} catch { Record 'T09' '安全卸载(保留用户内容)' 'FAIL' $_.Exception.Message; $env:USERPROFILE=$userHome; $env:APPDATA=$appData }

# ---------- T10 异常处理 ----------
try {
    # 10a: 缺模板 —— 复制 scripts 到无 templates 的目录运行
    $badDir = Join-Path $sandbox 'empty-scripts'
    Copy-Item (Join-Path $scriptDir 'install.ps1') $badDir -Force
    $r = Invoke-Ps (Join-Path $badDir 'install.ps1') @('-Targets','devin')
    Assert-True ($r.Code -ne 0) 'expected non-zero exit for missing template'
    Assert-True ($r.Output -match '找不到模板') 'error message missing'
    # 10b: 空环境卸载 → 优雅退出
    $u4 = Join-Path $sandbox 'case10'; $a4 = Join-Path $sandbox 'case10-ada'
    New-Item -ItemType Directory -Path $u4,$a4 -Force | Out-Null
    $env:USERPROFILE = $u4; $env:APPDATA = $a4
    $r2 = Invoke-Ps $uninstallPs1 @('-Force')
    $env:USERPROFILE = $userHome; $env:APPDATA = $appData
    Assert-True ($r2.Code -eq 0) "uninstall on empty env exit=$($r2.Code)"
    Assert-True ($r2.Output -match '无需卸载') 'expected no-op message'
    Record 'T10' '异常处理(缺模板/空环境)' 'PASS' ''
} catch { Record 'T10' '异常处理(缺模板/空环境)' 'FAIL' $_.Exception.Message; $env:USERPROFILE=$userHome; $env:APPDATA=$appData }

# ---------- T11 hooks 往返 ----------
try {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) { throw 'SKIP:no-node' }
    $u5 = Join-Path $sandbox 'case11'; $a5 = Join-Path $sandbox 'case11-ada'
    New-Item -ItemType Directory -Path $u5,$a5 -Force | Out-Null
    # 预置一个无关 hook，验证卸载不误删
    $cfg5 = Join-Path $a5 'devin\config.json'
    New-Item -ItemType Directory -Path (Split-Path $cfg5) -Force | Out-Null
    [System.IO.File]::WriteAllText($cfg5, '{"version":1,"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"echo unrelated","timeout":5}]}]}}', (New-Object System.Text.UTF8Encoding($false)))
    $env:USERPROFILE = $u5; $env:APPDATA = $a5
    $r = Invoke-Ps $installPs1 @('-Targets','devin','-IncludeHooks')
    Assert-True ($r.Code -eq 0) "install exit=$($r.Code) : $($r.Output)"
    $hook5 = Join-Path $a5 'devin\hooks\devin-chinese-thinking.mjs'
    Assert-True (Test-Path -LiteralPath $hook5) 'hook file missing'
    $cfgText = [System.IO.File]::ReadAllText($cfg5)
    Assert-True ($cfgText -match 'devin-chinese-thinking\.mjs') 'hook not registered'
    Assert-True ($cfgText -match 'echo unrelated') 'unrelated hook lost during install!'
    # hook 脚本本身可运行
    $hookOut = '{"test":1}' | & node $hook5 SessionStart 2>&1 | Out-String
    Assert-True ($hookOut -match 'additionalContext') 'hook script output invalid'
    # 卸载
    $r2 = Invoke-Ps $uninstallPs1 @('-Force')
    $env:USERPROFILE = $userHome; $env:APPDATA = $appData
    Assert-True ($r2.Code -eq 0) "uninstall exit=$($r2.Code)"
    $cfgAfter = [System.IO.File]::ReadAllText($cfg5)
    Assert-True ($cfgAfter -notmatch 'devin-chinese-thinking\.mjs') 'our hook entry remains'
    Assert-True ($cfgAfter -match 'echo unrelated') 'unrelated hook removed!'
    Assert-True (-not (Test-Path -LiteralPath $hook5)) 'hook file remains'
    Record 'T11' 'hooks 安装/卸载往返' 'PASS' ''
} catch {
    $env:USERPROFILE=$userHome; $env:APPDATA=$appData
    if ($_.Exception.Message -eq 'SKIP:no-node') { Record 'T11' 'hooks 安装/卸载往返' 'SKIP' 'node not found' }
    else { Record 'T11' 'hooks 安装/卸载往返' 'FAIL' $_.Exception.Message }
}

# ---------- T12 项目级安装 ----------
try {
    $pj = Join-Path $sandbox 'proj'; New-Item -ItemType Directory -Path $pj -Force | Out-Null
    $r = Invoke-Ps $installPs1 @('-Scope','project') $pj
    $rulePj = Join-Path $pj '.devin\rules\chinese-thinking.md'
    Assert-True (Test-Path -LiteralPath $rulePj) 'project rule missing'
    # 项目级安装不应创建全局规则文件（主沙箱中此前 -Targets all 已建，改用全新 case）
    $u7 = Join-Path $sandbox 'case12'; $a7 = Join-Path $sandbox 'case12-ada'
    New-Item -ItemType Directory -Path $u7,$a7 -Force | Out-Null
    $env:USERPROFILE = $u7; $env:APPDATA = $a7
    Invoke-Ps $installPs1 @('-Scope','project') $pj | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $u7 '.devin\rules\chinese-thinking.md'))) 'unexpected global write'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $a7 'devin\AGENTS.md'))) 'unexpected global AGENTS.md write'
    $env:USERPROFILE = $userHome; $env:APPDATA = $appData
    Record 'T12' '项目级 -Scope project' 'PASS' ''
} catch { $env:USERPROFILE=$userHome; $env:APPDATA=$appData; Record 'T12' '项目级 -Scope project' 'FAIL' $_.Exception.Message }

# ---------- T13 冲突不覆盖 ----------
try {
    $u6 = Join-Path $sandbox 'case13'; $a6 = Join-Path $sandbox 'case13-ada'
    New-Item -ItemType Directory -Path $u6,$a6 -Force | Out-Null
    $conflictPath = Join-Path $u6 '.devin\rules\chinese-thinking.md'
    New-Item -ItemType Directory -Path (Split-Path $conflictPath) -Force | Out-Null
    [System.IO.File]::WriteAllText($conflictPath, "# 用户自建同名规则`n- 我的内容不许被覆盖`n", (New-Object System.Text.UTF8Encoding($false)))
    $env:USERPROFILE = $u6; $env:APPDATA = $a6
    $r = Invoke-Ps $installPs1 @('-Targets','devin')
    $env:USERPROFILE = $userHome; $env:APPDATA = $appData
    $t = [System.IO.File]::ReadAllText($conflictPath)
    Assert-True ($t -match '我的内容不许被覆盖') 'unmanaged file overwritten!'
    Assert-True ($t -notmatch 'devin-chinese-thinking:v2') 'marker injected into unmanaged file'
    Assert-True ($r.Output -match 'conflict|未写入|不覆盖') 'conflict not reported'
    Record 'T13' '冲突不覆盖(同名非本项目文件)' 'PASS' ''
} catch { Record 'T13' '冲突不覆盖(同名非本项目文件)' 'FAIL' $_.Exception.Message; $env:USERPROFILE=$userHome; $env:APPDATA=$appData }

# ---------- T14 demo 离线 ----------
try {
    $demo = Join-Path $repoRoot 'demo\index.html'
    Assert-True (Test-Path -LiteralPath $demo) 'demo/index.html missing'
    $dt = [System.IO.File]::ReadAllText($demo)
    # 允许 xmlns 等命名空间声明；禁止 http(s) 外部资源加载
    $badRefs = [regex]::Matches($dt, '(?:src|href)\s*=\s*["'']https?://')
    Assert-True ($badRefs.Count -eq 0) "external resource refs: $($badRefs.Count)"
    Assert-True ($dt -match '模拟|SIMULATED|mock', 'demo missing simulated-data labels')
    Record 'T14' 'demo 离线可用' 'PASS' ''
} catch { Record 'T14' 'demo 离线可用' 'FAIL' $_.Exception.Message }

# ---------- T15 status.ps1 ----------
try {
    $r = Invoke-Ps $statusPs1 @()
    Assert-True ($r.Code -eq 0) "status exit=$($r.Code)"
    Assert-True ($r.Output -match '检查结果') 'status output incomplete'
    Record 'T15' 'status.ps1 只读检查' 'PASS' ''
} catch { Record 'T15' 'status.ps1 只读检查' 'FAIL' $_.Exception.Message }

# ---------- T16 detect_language + status -Track ----------
try {
    $detectPs1 = Join-Path $scriptDir 'detect_language.ps1'
    $enSample = Join-Path $sandbox 'en.txt'
    $zhSample = Join-Path $sandbox 'zh.txt'
    [System.IO.File]::WriteAllText($enSample, "I will inspect the repository structure first and then read the main entry file carefully.`n`nThen I need to check the test configuration before making changes.`n", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($zhSample, "我先查看目录结构。`n`n然后读取主入口文件。`n`n最后运行测试验证。`n", (New-Object System.Text.UTF8Encoding($false)))
    $rEn = Invoke-Ps $detectPs1 @('-TextFile', $enSample)
    $rZh = Invoke-Ps $detectPs1 @('-TextFile', $zhSample)
    Assert-True ($rEn.Code -eq 0 -and $rEn.Output -match '漂移|drift_ratio') "en detect failed: $($rEn.Output)"
    Assert-True ($rZh.Code -eq 0 -and $rZh.Output -match '中文为主') "zh detect failed: $($rZh.Output)"
    # status -Track 在沙箱写 state.json（Devin 不存在 → not-detected，不写状态，验证不崩即可）
    $rSt = Invoke-Ps $statusPs1 @('-Track')
    Assert-True ($rSt.Code -eq 0) "status -Track exit=$($rSt.Code)"
    Record 'T16' 'detect_language + status -Track' 'PASS' ''
} catch { Record 'T16' 'detect_language + status -Track' 'FAIL' $_.Exception.Message }

# ---------- T17 skill 安装/卸载往返 ----------
try {
    $u8 = Join-Path $sandbox 'case17'; $a8 = Join-Path $sandbox 'case17-ada'
    New-Item -ItemType Directory -Path $u8,$a8 -Force | Out-Null
    # 预置一个无关 skill，验证不误删
    $otherSkill = Join-Path $a8 'devin\skills\other-skill\SKILL.md'
    New-Item -ItemType Directory -Path (Split-Path $otherSkill) -Force | Out-Null
    [System.IO.File]::WriteAllText($otherSkill, "---`nname: other-skill`n---`nuser skill`n", (New-Object System.Text.UTF8Encoding($false)))
    $env:USERPROFILE = $u8; $env:APPDATA = $a8
    $r = Invoke-Ps $installPs1 @('-Targets','devin')
    Assert-True ($r.Code -eq 0) "install exit=$($r.Code) : $($r.Output)"
    $skillDst = Join-Path $a8 'devin\skills\chinese-thinking\SKILL.md'
    Assert-True (Test-Path -LiteralPath $skillDst) 'skill file missing'
    $st = [System.IO.File]::ReadAllText($skillDst)
    Assert-True ($st -match 'devin-chinese-thinking:v2-skill') 'skill marker missing'
    Assert-True ($st -match 'name:\s*chinese-thinking') 'skill frontmatter invalid'
    # 重复安装幂等
    $r2 = Invoke-Ps $installPs1 @('-Targets','devin')
    Assert-True ($r2.Output -match 'skipped-already-installed|已安装') 'skill not idempotent'
    # 卸载
    $r3 = Invoke-Ps $uninstallPs1 @('-Force')
    $env:USERPROFILE = $userHome; $env:APPDATA = $appData
    Assert-True ($r3.Code -eq 0) "uninstall exit=$($r3.Code)"
    Assert-True (-not (Test-Path -LiteralPath $skillDst)) 'skill file remains'
    Assert-True (Test-Path -LiteralPath $otherSkill) 'unrelated skill removed!'
    Record 'T17' 'skill 安装/卸载往返' 'PASS' ''
} catch { $env:USERPROFILE=$userHome; $env:APPDATA=$appData; Record 'T17' 'skill 安装/卸载往返' 'FAIL' $_.Exception.Message }

# ---------- 汇总 ----------
Write-Host ''
Write-Host '===== 测试结果汇总 =====' -ForegroundColor White
$results | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "PASS: $script:pass   FAIL: $script:fail   SKIP: $script:skip" -ForegroundColor $(if ($script:fail -gt 0) {'Red'} else {'Green'})

# 恢复环境
$env:USERPROFILE = $realUserProfile
$env:APPDATA = $realAppData
Set-Location $realPwd

if ($script:fail -gt 0) { exit 1 } else { exit 0 }
