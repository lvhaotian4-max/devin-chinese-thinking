# Changelog

## [Unreleased] — v2 升级

### 新增

- `templates/chinese-thinking-v2.md`：适配 `.devin/rules/*.md` 的
  `always_on` frontmatter 规则，覆盖可见分析、计划、工具调用说明、
  子代理可见输出、错误与总结；明确区分可见 Thoughts 与不可见内部推理。
- `scripts/install.ps1`：Windows 一键安装，支持用户级/项目级、
  新旧路径、自动备份、幂等更新、UTF-8 无 BOM 编码、冲突不覆盖。
- `scripts/doctor.ps1`：只读体检——路径、标记、编码、frontmatter、
  冲突检测与人工验证指引。
- `scripts/uninstall.ps1`：仅移除本项目管理内容，支持 `-Restore`
  从备份恢复；不触碰用户自有规则。
- `tests/check_drift.py`：可见文本语言漂移统计（JSON/CSV、基线对比），
  剔除代码块、日志、URL、路径、标识符；不读取隐藏推理。
- `tests/test_check_drift.py`：19 个离线单元测试（标准库 unittest）。
- `docs/manual-test-matrix.md`：Code / Plan / Ask / Subagent / 长上下文
  等场景的人工测试矩阵。
- `docs/compatibility.md`：规则加载机制核对与实测环境记录表。
- `docs/ollama-fallback.md`：可选本地 Ollama 翻译兜底**设计稿**
  （未实现，不触碰 Devin 安装目录与网络层）。

### 修正（审计结论）

- `docs/mechanism.md`：补充新版 `.devin/` 与旧版 `.windsurf/`、
  codeium memories 路径区分；修正"思考链不展示但界面可见"的矛盾表述，
  明确区分可见 Thoughts 与不可见内部推理。
- 软化绝对化表述："全程中文""推理质量不受影响""不会被更新覆盖"
  等改为倾向性/经验性描述，标注待验证项。
- 保留全部原有截图与作者署名信息。

### 未验证（待人工测试）

- v2 模板在真实 Devin 会话中的语言稳定性（见测试矩阵）。
- `.devin/rules` 路径在 Devin Desktop IDE（非 CLI）下的实际加载行为。
- Ollama 兜底模块：仅设计，未实现。
