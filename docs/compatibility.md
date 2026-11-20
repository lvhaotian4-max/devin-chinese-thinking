# 兼容性与实测环境记录

> 原则：只记录**有证据**的结论。"理论上有效"不等于"已验证"。
> 截图证据见 `assets/screenshot.jpg`（作者实测环境，单次会话）。

## 规则加载机制（依据 Devin 官方文档）

本机随 Devin Desktop 安装的官方文档
`resources/app/extensions/windsurf/devin/share/devin/docs/extensibility/rules.mdx`
确认以下加载路径：

| 层级 | 路径 | 机制 |
|---|---|---|
| 项目 | `AGENTS.md` / `AGENTS.local.md` / `AGENT.md` / `.windsurfrules` / `CLAUDE.md` | 自动加载，always-on |
| 项目 | `.devin/rules/*.md` | 每文件一条规则，`trigger` frontmatter（含 `always_on`） |
| 项目 | `.devin/global_rules.md` | 单文件 always-on |
| 项目 | `.windsurf/rules/*.md`、`.windsurf/global_rules.md` | 旧版兼容，`.devin/` 优先 |
| 用户（全局） | `%APPDATA%\devin\AGENTS.md`（Win）/ `~/.config/devin/AGENTS.md` | 每次会话加载 |
| 用户（全局） | `~/.devin/rules/*.md`、`~/.devin/global_rules.md` | 每次会话加载 |
| 用户（全局） | `~/.claude/CLAUDE.md` | 兼容读取 |
| 旧版 | `~/.codeium/windsurf/memories/global_rules.md` | Windsurf 记忆规则，仍被读取 |

## 适用版本记录表

| 产品 / 版本 | 规则路径 | 状态 | 证据 |
|---|---|---|---|
| Devin Desktop（作者环境，2025–2026） | `%APPDATA%\devin\AGENTS.md` + `~/.codeium/windsurf/memories/global_rules.md` | ✅ 作者实测有截图 | `assets/screenshot.jpg` |
| Devin CLI | 同上全局路径 | ⚠️ 文档确认加载机制，语言效果待人工复测 | 官方 rules.mdx |
| SWE-2 / SWE-2 Flash | 不依赖版本，取决于规则注入 | ⚠️ 作者实测；其他模型未验证 | 截图 + 规则文件 |
| `.devin/rules/*.md`（v2 新模板） | 项目级 / `~/.devin/rules/` | ⚠️ 官方文档确认支持 `always_on`；v2 模板的实际语言效果**待人工测试** | rules.mdx + `docs/manual-test-matrix.md` |
| 其他 Windsurf 系 Agent | `.windsurf/rules/`、codeium memories | ⚠️ 理论兼容，未实测 | — |

## 已知限制（诚实声明）

- 规则只能提高中文输出的**倾向性**，不能保证 100% 不漂移；
  长上下文、模式切换、模型版本变化都可能影响效果。
- 不可见的内部推理不在规则可控范围，本项目不对其做任何承诺。
- 规则文件是用户级配置，一般不会被产品更新覆盖；但官方若调整
  规则路径或加载机制，旧路径可能失效，需以官方文档为准。
- `check_drift.py` 统计的是**用户提供的可见文本**，不代表模型
  内部推理语言，也不能单独证明规则生效。
