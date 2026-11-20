<div align="center">

![banner](assets/banner.jpg)

# 🧠 Devin 思考链汉化

**让 Devin全部模型 的可见思考说明（Thoughts / reasoning trace）更稳定地使用简体中文输出**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)]()
[![Devin](https://img.shields.io/badge/Devin-CLI%20%2F%20Desktop-0b5fff)](https://devin.ai)

[快速开始](#-快速开始) · [原理解析](docs/mechanism.md) · [模板下载](#-可直接复制的模板) · [常见问题](#-常见问题-faq) · [English](README.en.md)

</div>

---

## ✨ 效果预览

配置完成后，Devin 在执行任务时**展示给用户的思考说明、计划、工具调用前的说明和总结**将以简体中文为主，而不是默认的英文。

> 💡 思考说明是模型的"内心独白"的可见部分。把它变成中文后，审查 AI 的推理逻辑、调试 Agent 行为都会方便得多。
> 注意：规则提高的是**倾向性**而非硬性保证，模型、版本或长上下文仍可能出现漂移；不可见的内部推理不在可控范围。详见 [兼容性说明](docs/compatibility.md)。

![效果预览](assets/screenshot.jpg)

## 🎯 适用范围

| 产品 / 模型 | 状态 | 说明 |
|---|---|---|
| Devin Desktop（IDE 内置 Agent） | ✅ 作者实测 | 见 `assets/screenshot.jpg`，单次会话证据 |
| Devin CLI | ⚠️ 机制已确认 | 官方文档确认规则加载，语言效果待复测 |
| SWE-2 Flash | ✅ 作者实测 | 同上 |
| `.devin/rules` v2 模板 | ⚠️ 待人工测试 | 官方文档支持 `always_on`，效果见 [测试矩阵](docs/manual-test-matrix.md) |
| 其他基于 Windsurf 规则体系的 Agent | ⚠️ 理论兼容 | 未实测 |

## 🚀 快速开始

整个配置只需要 **2 分钟**。Windows 用户推荐使用一键脚本；也可以手工配置。

### 方式 A：一键脚本（Windows，推荐）

```powershell
# 克隆本仓库后，在仓库根目录执行：
git clone https://github.com/lvhaotian4-max/devin-chinese-thinking
cd devin-chinese-thinking
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -Targets all
```

- 自动识别新版（`~/.devin/rules/`、`%APPDATA%\devin\AGENTS.md`）与旧版
  （`.codeium/windsurf/memories/global_rules.md`）路径；
- 修改已有文件前自动备份为 `.bak-<时间戳>`；重复运行幂等；
- 已有非本项目管理的同名文件时**不覆盖**，只报告冲突。

验证与维护：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1      # 体检（只读）
powershell -ExecutionPolicy Bypass -File scripts\uninstall.ps1   # 卸载（可 -Restore 恢复备份）
```

### 方式 B：手工配置

Devin 会读取多类 always-on 规则文件，**新版优先用 `.devin/rules/`**：

| 文件路径 | 作用域 | 新旧 |
|---|---|---|
| `%USERPROFILE%\.devin\rules\chinese-thinking.md`（Windows）<br>`~/.devin/rules/chinese-thinking.md`（macOS/Linux） | 全局 | 新版，支持 `trigger: always_on` |
| `%APPDATA%\devin\AGENTS.md`（Windows）<br>`~/.config/devin/AGENTS.md`（macOS/Linux） | 全局 | 新版 |
| `%USERPROFILE%\.codeium\windsurf\memories\global_rules.md` | 全局 | 旧版兼容，仍被读取 |

> Windows 上的实际路径示例：`C:\Users\<你的用户名>\.devin\rules\chinese-thinking.md`

如果文件不存在，**直接创建**即可；如果已存在，**追加**规则内容，不要覆盖原有规则。

### 写入语言规则

把 [`templates/chinese-thinking-v2.md`](templates/chinese-thinking-v2.md) 的**完整内容**（含 frontmatter）复制为上述 `.devin/rules/` 下的规则文件；或把**正文部分**追加到 `AGENTS.md` / `global_rules.md`。

v2 模板相对 v1 的改进：

- 覆盖可见分析、计划、工具调用说明、子代理输出、错误与总结；
- 针对英文日志、英文代码、长上下文、模式切换的漂移给出约定；
- 明确保留代码、路径、API、SQL、JSON、日志原文；
- 明确区分可见 Thoughts 与不可见内部推理，不虚构控制能力；
- 规则更精简，减少对上下文的占用。

旧版简洁模板仍保留在 [`templates/language-rules.md`](templates/language-rules.md)，可按需使用。

### 第 3 步：重启会话并验证

1. 重启 Devin（或新开一个会话），让规则重新加载；
2. 随便给 Agent 一个任务，例如：`帮我看看这个文件夹里有什么`；
3. 观察 Agent 的思考链输出 —— 应该全程是中文。

## 📁 本仓库结构

```
devin-chinese-thinking/
├── README.md                  ← 本文件：快速上手指南
├── README.en.md               ← English guide
├── CHANGELOG.md               ← 版本变更记录
├── docs/
│   ├── mechanism.md           ← 深度解析：为什么这样能生效
│   ├── compatibility.md       ← 规则加载机制核对 + 实测环境记录
│   ├── manual-test-matrix.md  ← 人工测试矩阵（真实 Devin 验证用）
│   └── ollama-fallback.md     ← 可选本地翻译兜底（设计稿）
├── templates/
│   ├── chinese-thinking-v2.md ← v2 规则模板（.devin/rules always_on，推荐）
│   ├── language-rules.md      ← v1 语言规则模板（简洁版，仍可用）
│   └── project-agents.md      ← 项目级 AGENTS.md 模板
├── scripts/                   ← Windows 一键脚本（install/doctor/uninstall）
├── tests/                     ← check_drift.py 漂移统计 + 离线单元测试
├── assets/                    ← banner、截图、打赏码
└── LICENSE                    ← MIT 协议
```

## 💡 进阶用法

### 只对某一个项目生效

如果你不想全局汉化，可以把规则写进**项目根目录的 `AGENTS.md`**，只对该仓库的会话生效。模板见 [`templates/project-agents.md`](templates/project-agents.md)。

### 与其他规则共存

语言规则只是众多 always-on 规则中的一条。你可以把它和代码风格、构建命令、安全规范等规则写在同一个文件里，Devin 会综合遵循。建议把语言规则放在文件**靠前的位置**，权重更高。

### 子代理也会被覆盖

v2 规则明确要求子代理可见输出遵循同一语言规则，并建议在派生 subagent 的任务描述中重申"可见输出使用简体中文"。

### 漂移了怎么办：离线统计可见文本

把 Devin 界面中复制出的可见文本保存为 `.txt`，用 `tests/check_drift.py` 统计中英文分布：

```bash
python tests/check_drift.py visible.txt          # JSON 报告
python tests/check_drift.py visible.txt --format csv
# 基线对比：先后两次生成 JSON 报告，再对比
python tests/check_drift.py --compare base.json new.json
```

它会剔除代码块、日志、URL、路径和技术标识符，只统计自然语言段落。
**注意**：它只分析你提供的文本，不读取隐藏推理，也不能单独证明规则生效——真实效果仍需人工观察，测试方法见 [docs/manual-test-matrix.md](docs/manual-test-matrix.md)。

### 可选：本地 Ollama 翻译兜底（设计稿）

若规则生效不完整，可考虑用本机 Ollama 把复制出的英文可见文本翻成中文对照。当前仅为设计方案，见 [docs/ollama-fallback.md](docs/ollama-fallback.md)——不触碰 Devin 安装目录，不劫持网络，可独立关闭。

## ❓ 常见问题 FAQ

**Q：必须两个文件都配置吗？**
A：不需要，任选其一即可。Windows 上推荐直接用 `scripts/install.ps1 -Targets all` 一次配齐新旧路径。

**Q：能保证思考说明 100% 中文吗？**
A：不能。规则提高中文输出的倾向性，但模型版本、上下文长度、模式切换都可能造成漂移。可用 `tests/check_drift.py` 量化可见文本的漂移程度，真实效果以人工测试为准（见测试矩阵）。

**Q：规则能控制"真正的内部推理"吗？**
A：不能，也不应声称能。模型不可见的内部推理不在规则可控范围；本项目约束的是界面中**可见**的思考说明、计划、工具说明和回复。可见文本由模型显式生成，用中文生成而非事后翻译，推理逻辑不受影响（此为经验观察，未经严格基准验证）。

**Q：会影响代码注释和输出语言吗？**
A：v2 规则默认代码注释用简体中文，技术标识符（变量名、API 名、路径、SQL、JSON、日志原文）保持原文。如果你希望代码注释也用英文，删掉规则里对应一条即可。

**Q：Devin 更新后会失效吗？**
A：规则文件是用户级配置，一般不会被产品更新覆盖；但官方若调整规则路径或加载机制，旧路径可能失效，需以官方文档为准并运行 `doctor.ps1` 检查。

**Q：可以汉化成其他语言吗？**
A：可以。把"简体中文"替换成目标语言（如 English、日本語）即可，原理相同。

## 🙏 致谢

本方案源自实际使用中验证可行的配置实践，感谢 Devin / Windsurf 规则体系对用户自定义指令的支持。

## ☕ 打赏支持

如果这个项目对你有帮助，欢迎请我喝杯咖啡 ☕

| 微信支付 | 支付宝 |
|---|---|
| ![微信收款码](assets/wechat-qr.jpg) | ![支付宝收款码](assets/alipay-qr.jpg) |

> 打赏完全自愿，Star ⭐ 就是最大的支持！

## 📄 License

[MIT](LICENSE) — 随便用，欢迎 Star ⭐
