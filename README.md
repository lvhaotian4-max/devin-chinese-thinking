<div align="center">

# 🧠 Devin 中文思考规则

**让 Devin / SWE-2 / SWE-2 Flash 在界面中展示的可见文本——思考说明、计划、工具调用说明、回复和总结——尽量使用简体中文**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)]()
[![Verified](https://img.shields.io/badge/verified-Devin%20Desktop%201.141.2-brightgreen)]()

[快速开始](#-快速开始) · [在线演示](demo/index.html) · [原理](docs/中文思考规则实现原理.md) · [安装详解](docs/Windows安装与卸载.md) · [验证记录](docs/真实效果验证.md) · [English](README.en.md)

</div>

---

## ⚠️ 先说清楚：它是什么、不是什么

| ✅ 它能做的 | ❌ 它不能做的 |
|---|---|
| 通过规则文件 + 可选 hook 让 Agent **倾向于**用中文生成可见文本 | 保证 100% 不漂移（长上下文、模式切换仍可能英文） |
| 约束界面中**可见**的思考说明、计划、工具说明、回复 | 控制模型**不可见的内部推理**（无法观测、无法证明） |
| 一键安装/备份/幂等/安全卸载，不碰 Devin 程序本体 | 修改 Devin 安装目录、劫持网络、注入客户端 |
| 可选本地 Ollama 翻译你复制出的文本 | 自动抓取界面做实时翻译（无官方接口，未实现） |

> **"规则请求中文输出" ≠ "已证明隐藏内部推理是中文"。**
> 本项目只约束模型显式生成、展示给用户的文本。

## 🎯 目前实际支持什么

| 产品 / 模型 | 状态 | 证据 |
|---|---|---|
| Devin Desktop 1.141.2 + SWE-2 | ✅ 本会话实测中文输出 | 本仓库 V2 升级会话本身 |
| SWE-2 Flash / SWE-2 1.6 Slow / Kimi / Claude / Gemini / GLM | ⚠️ 机制覆盖（模型无关注入），均未实测 | 见[模型覆盖矩阵](docs/compatibility.md#模型覆盖矩阵) |
| 规则文件（AGENTS.md / codeium memories） | ✅ 实测被加载 | 会话系统提示中的 rules 块 |
| 生命周期 hook（每次提问重注入） | ✅ 官方文档 + 本机生效中 | `lifecycle-hooks.mdx` + 本会话注入记录 |
| `~/.devin/rules/*.md` | ⚠️ 文档确认，Desktop 实测待补 | 官方 `rules.mdx` |
| Devin CLI | ⚠️ 机制相同，未实测 | 本机无 CLI |
| macOS / Linux | ⚠️ 路径有文档依据，脚本仅 Windows | — |
| Ollama 翻译原型 | ✅ `--mock` 已测；真实翻译未验证 | 需本机 Ollama |

**版本更新与汉化检测**：`status.ps1 -Track` 会记录 Devin 版本号，
下次运行自动提示"版本已变化"；`detect_language.ps1 -TextFile out.txt`
分析你从界面复制出的可见文本，报告中文/英文占比与漂移判定
（只统计可见文本，不涉及隐藏推理）。

详细验证状态见 [`docs/真实效果验证.md`](docs/真实效果验证.md) 和
[`docs/V2升级验收报告.md`](docs/V2升级验收报告.md)。

## 🚀 快速开始（Windows）

```powershell
git clone https://github.com/lvhaotian4-max/devin-chinese-thinking
cd devin-chinese-thinking

# 安装规则（新旧路径都写，自动备份、幂等、不覆盖你的其他规则）
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -Targets all

# 推荐：加装 hook —— 每次提问重新注入语言指令，抗漂移最强（需 node）
powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -Targets all -IncludeHooks

# 检查状态（只读）
powershell -ExecutionPolicy Bypass -File scripts\status.ps1

# 重启 Devin Desktop 或新开会话，然后给 Agent 一个任务观察输出
```

卸载：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\uninstall.ps1          # 预览+确认
powershell -ExecutionPolicy Bypass -File scripts\uninstall.ps1 -Force    # 直接卸载
powershell -ExecutionPolicy Bypass -File scripts\uninstall.ps1 -Restore  # 从 .bak 备份回滚
```

手工配置、项目级安装、macOS/Linux 路径见
[`docs/Windows安装与卸载.md`](docs/Windows安装与卸载.md) 和
[`docs/完整运行流程.md`](docs/完整运行流程.md)。

## 🖥️ 在线演示

[`demo/index.html`](demo/index.html) —— 纯离线 HTML 演示，双击即可打开，
无需联网。包含：配置检测模拟、安装流程模拟、中英效果对比、工作原理、
故障诊断、卸载流程。**页面内所有检测数据均为模拟数据**，有显著标注。

![demo 截图](assets/screenshots/demo-overview.png)

真实效果截图（作者早期实测，v1 配置，单次会话）：

![效果预览](assets/screenshot.jpg)

## 🧩 工作原理（简版）

```
规则模板 → install.ps1 写入+备份 → Devin 会话启动注入 / hook 每次提问注入
        → 模型倾向用中文生成可见文本 → 界面输出中文
```

三层机制可叠加：`~/.devin/rules/*.md`（always_on）、
`%APPDATA%\devin\AGENTS.md` 标记块、codeium memories（旧版兼容），
外加可选 hook（`config.json` → `SessionStart`/`UserPromptSubmit`
→ `additionalContext`，每轮重注入，抗漂移最强）。

完整链路与边界说明：[docs/中文思考规则实现原理.md](docs/中文思考规则实现原理.md)

## 🧪 验证与测试

```powershell
# 沙箱自动化测试（15 项，不动真实配置）
powershell -ExecutionPolicy Bypass -File scripts\test.ps1

# 可见文本漂移统计（把 Devin 界面复制出的文本存为 .txt）
python tests\check_drift.py visible.txt
python tests\check_drift.py --compare base.json new.json

# 可选：本地 Ollama 翻译对照（仅处理你提供的文本）
python scripts\translate_ollama.py visible.txt --mock   # 离线演示
python scripts\translate_ollama.py visible.txt          # 需本机 Ollama
```

本仓库 V2 验收：沙箱测试 **15/15 通过**，Python 单测 **19/19 通过**，
Devin Desktop 中文输出经本会话实测。逐项记录见
[`docs/V2升级验收报告.md`](docs/V2升级验收报告.md)。

## 📁 仓库结构

```
devin-chinese-thinking/
├── README.md / README.en.md
├── CHANGELOG.md
├── demo/index.html               ← 离线演示（模拟数据已标注）
├── docs/
│   ├── 项目现状审计.md            ← 升级前审计（含 hooks 机制发现）
│   ├── 中文思考规则实现原理.md     ← 端到端链路 + 边界澄清
│   ├── 完整运行流程.md            ← 安装→验证→卸载全步骤
│   ├── Windows安装与卸载.md       ← 脚本参数与路径详解
│   ├── 真实效果验证.md            ← 已验证/未验证清单
│   ├── 常见问题与解决方案.md
│   ├── 兼容性与技术限制.md
│   ├── V2升级验收报告.md          ← 测试执行记录
│   ├── mechanism.md / compatibility.md / manual-test-matrix.md
│   └── ollama-fallback.md        ← Ollama 翻译说明
├── templates/                    ← v2 always_on 规则等模板
├── scripts/                      ← install/status(uninstall)/test/translate
├── assets/hooks/                 ← hook 脚本模板
├── assets/screenshots/           ← demo 真实渲染截图
└── tests/                        ← check_drift.py + 单测
```

## ❓ FAQ

**Q：能保证思考说明 100% 中文吗？**
A：不能。规则提高倾向性，长上下文/模式切换/模型版本仍可能漂移。
抗漂移最强手段是 `-IncludeHooks`（每次提问重注入）。

**Q：规则能控制"真正的内部推理"吗？**
A：不能，本项目不做此声称。约束的是界面**可见**文本。

**Q：我的其他规则会被覆盖吗？**
A：不会。所有写入要么新建文件、要么追加带标记的块；已有非本项目
文件只报告冲突不覆盖；卸载只删本项目标记内容。

**Q：Devin 更新后会失效吗？**
A：规则是用户级配置一般不被覆盖；若官方改路径，`status.ps1` 会显示
MISSING，以官方文档为准。

**Q：macOS/Linux 呢？**
A：手工把 `templates/chinese-thinking-v2.md` 放到
`~/.devin/rules/` 或追加到 `~/.config/devin/AGENTS.md`；
PowerShell 脚本仅 Windows。

**Q：Ollama 是必须的吗？**
A：不是。纯可选，用于把你复制出的英文可见文本翻成中文对照。

## 📄 License

[MIT](LICENSE)
