# Windows 安装与卸载详解

## 安装脚本一览

| 脚本 | 作用 | 是否修改文件 |
|---|---|---|
| `install.ps1` | 安装规则（+可选 hook） | 是（写用户目录，先备份） |
| `status.ps1` | 检查安装状态 + Devin 版本跟踪（`-Track`） | 否（只读；-Track 写一个小状态文件） |
| `detect_language.ps1` | 检测可见文本汉化程度（中英文占比） | 否 |
| `doctor.ps1` | status.ps1 的兼容别名 | 否 |
| `uninstall.ps1` | 卸载规则与 hook | 是（只删本项目内容） |
| `test.ps1` | 沙箱自动化测试 | 只写 %TEMP% 沙箱 |

## install.ps1 参数

```powershell
install.ps1 [-Scope user|project] [-Targets devin|legacy|all]
            [-IncludeHooks] [-WhatIfOnly]
```

- `-Scope user`（默认）：写用户级全局规则，所有项目生效；
- `-Scope project`：写当前目录 `.devin\rules\`，仅该项目生效；
- `-Targets devin`（默认）：`~/.devin/rules/` + `%APPDATA%\devin\AGENTS.md`；
- `-Targets legacy`：仅 codeium memories 旧路径；
- `-Targets all`：新旧都装（推荐）；
- `-IncludeHooks`：额外安装 `SessionStart`/`UserPromptSubmit` hook，
  需要本机 node；检测到已有 chinese-thinking hook 时自动跳过；
- `-WhatIfOnly`：只打印将执行的操作。

### 它写入的确切位置（Windows）

| 目标 | 路径 | 方式 |
|---|---|---|
| 新版规则 | `%USERPROFILE%\.devin\rules\chinese-thinking.md` | 新建文件（含 frontmatter） |
| 全局规则 | `%APPDATA%\devin\AGENTS.md` | 追加 `<!-- devin-chinese-thinking:v2 -->` 标记块 |
| 旧版兼容 | `%USERPROFILE%\.codeium\windsurf\memories\global_rules.md` | 同上 |
| hook（可选） | `%APPDATA%\devin\hooks\devin-chinese-thinking.mjs` + `config.json` 合并 | 新建 + JSON 合并 |

**不写**：`D:\Devin` 等 Devin 安装目录、注册表、其他 Agent 的配置。

## 安装行为保证

- **备份**：凡是修改已存在的文件，先复制为 `<文件>.bak-yyyyMMdd-HHmmss`；
- **幂等**：重复运行检测到标记后跳过或原位更新，不产生重复块；
- **不覆盖**：目标文件存在但无本项目标记时，报
  `conflict-manual-merge` 并跳过，需手动合并；
- **编码**：全部 UTF-8 无 BOM；
- **冲突处理**：hook 安装前检测 config.json 中已有
  `chinese-thinking*.mjs` 引用则跳过，避免双重注入；
- **config.json 解析失败**时不修改该文件，仅报告错误。

## status.ps1 检查项

1. Devin Desktop 安装探测（已知路径 + 运行中进程兜底）；
2. node 可用性（hook 依赖）；
3. 8 个候选规则路径：存在性、UTF-8 BOM、项目标记、语言规则特征、
   frontmatter；
4. `config.json` 中本项目 hook 的注册状态；
5. 冲突分析（本项目管理 vs 用户自有语言规则）；
6. 人工验证加载的分步指引。

输出中的状态含义：`exists` `utf8-nobom`/`UTF8-BOM!` `managed-by-project`/
`user-content` `lang-rule-found`/`no-lang-rule` `frontmatter-ok`/`frontmatter-missing`。

## uninstall.ps1 行为

| 对象 | 行为 |
|---|---|
| `~/.devin/rules/chinese-thinking.md` 等独立规则文件 | 含本项目签名才删除；同名用户文件跳过并告警 |
| AGENTS.md / global_rules.md | 只移除标记块，其他内容保留 |
| config.json | 只移除 command 引用 `devin-chinese-thinking.mjs` 的 hook 条目；你自建的其他 hook 保留；处理前备份 |
| `hooks/devin-chinese-thinking.mjs` | 含本项目标记才删除；`-Restore` 模式下保留 |
| `*.bak-*` 备份 | 永不删除；`-Restore` 恢复最近一份 |

疑似 v1 手工配置（含 chinese-thinking 字样但无标记块）**不会自动删除**，
只告警请人工处理。

## 常见安装问题

- **ExecutionPolicy 拦截**：所有示例均带 `-ExecutionPolicy Bypass`；
  也可对当前用户放开：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`。
- **config.json 被改坏**：安装前自动备份；若 ConvertFrom-Json 失败会放弃修改。
  恢复：`uninstall.ps1 -Restore` 或手动复制 `.bak-*` 回去。
- **想只装 hook 不装规则**：目前不支持单独安装 hook；hook 的价值依赖
  规则文件同时存在，二者互补。
