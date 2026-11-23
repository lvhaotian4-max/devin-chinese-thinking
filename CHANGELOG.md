# Changelog

## [2.1.0] — 2026-11-23 检测能力增强

### 新增

- `scripts/detect_language.ps1`：可见文本汉化检测——优先调用
  `check_drift.py`（Python），无 Python 时内置近似统计；输出
  drift_ratio 与判定（<0.1 中文为主 / ≤0.3 偶发漂移 / >0.3 漂移明显）。
  明确声明：只分析用户提供的可见文本，不涉及隐藏推理。
- `status.ps1 -Track`：记录 Devin Desktop 版本号到
  `%APPDATA%\devin-chinese-thinking\state.json`，下次运行自动对比
  并在版本变化时提示复查规则；默认仍只读。
- 模型覆盖矩阵（`docs/compatibility.md`）：SWE-2 已实测；
  SWE-2 Flash / SWE-2 1.6 Slow / Kimi / Claude / Gemini / GLM
  机制覆盖但均未实测，附逐模型验证方法。
- `test.ps1` 新增 T16（detect_language + status -Track），共 16 项。

### 说明

- 规则与 hook 为模型无关的上下文指令，所有模型"机制上都覆盖"，
  但各模型对中文指令的遵循度不同，文档已如实区分。
- 脚本侧无法读取隐藏思维链；"思维链是否汉化"只能通过
  detect_language.ps1 分析用户复制出的可见文本来近似判断。

## [2.0.0] — 2026-11-23 V2 全面升级

### 新增

- **审计**：`docs/项目现状审计.md` —— 仓库与本机实际生效配置对照；
  发现并补齐了文档完全缺失的 **hooks 机制**（`config.json` +
  `SessionStart`/`UserPromptSubmit` 注入），这很可能是当前环境
  中文输出最稳定的来源。
- **Hooks 支持**：`install.ps1 -IncludeHooks` 安装
  `assets/hooks/devin-chinese-thinking.mjs` 并合并 `config.json`
  （备份、幂等、检测已有 chinese-thinking hook 则跳过）；
  `uninstall.ps1` 精确移除本项目 hook 条目而保留用户自建 hook。
- **`scripts/status.ps1`**：只读体检——Devin Desktop 探测、node 检测、
  8 个候选路径、编码/frontmatter/标记、hook 注册状态、冲突分析；
  `doctor.ps1` 保留为兼容别名。
- **`scripts/test.ps1`**：沙箱自动化测试 15 项（USERPROFILE/APPDATA
  重定向），覆盖首装/重装/保留/更新/缺失/编码/中文/备份恢复/
  安全卸载/异常/hooks 往返/项目级/冲突/demo 离线/status。
- **`demo/index.html`**：纯离线中文演示（配置检测、安装模拟、
  中英对比、原理、故障诊断、卸载流程），全部数据标注"模拟"。
- **`scripts/translate_ollama.py`**：可选本地 Ollama 翻译原型——
  用户主动提供文本，localhost 限定、代码/路径保护、缓存去重、
  失败重试、`--mock` 模拟模式；原生实时集成明确未实现。
- **文档 ×7**：`中文思考规则实现原理.md`、`完整运行流程.md`、
  `Windows安装与卸载.md`、`真实效果验证.md`、`常见问题与解决方案.md`、
  `兼容性与技术限制.md`、`V2升级验收报告.md`。
- **`assets/screenshots/`**：demo 界面真实渲染截图（headless Edge）。

### 修正

- README.md / README.en.md 全面重写：如实标注验证状态，
  删除无证据的绝对化表述，补充 demo 入口、hooks 机制、文档导航。
- `docs/mechanism.md` / `compatibility.md`：补充 hooks 链路与
  Desktop 1.141.2 实测记录。
- `docs/ollama-fallback.md`：由"设计稿"更新为"原型已实现"，
  保留原生集成未实现的声明。

### 验证状态（详见 V2升级验收报告.md）

- ✅ 沙箱测试 15/15、Python 单测 19/19、translate --mock、
  Devin Desktop 本会话中文输出（端到端真实证据）
- ⚠️ `~/.devin/rules` 在 Desktop 的实际加载、长上下文漂移率、
  子代理专项、Devin CLI、macOS/Linux —— 未验证
- ❌ 原生实时翻译集成 —— 未实现（无官方接口）

## [1.x] — 旧版本

- v1：语言规则模板 + 手工配置指南 + 效果截图（作者实测，单次会话）。
- v2 初版（本仓库上一提交）：always_on 规则模板、install/doctor/
  uninstall 脚本、check_drift.py 漂移统计、测试矩阵与设计稿文档。
