# 语言规则完整模板

> 使用方法：复制以下全部内容，追加到你的全局规则文件中：
> - Windows（Windsurf 记忆）：`%USERPROFILE%\.codeium\windsurf\memories\global_rules.md`
> - Windows（Devin 全局）：`%APPDATA%\devin\AGENTS.md`
> - macOS / Linux：`~/.config/devin/AGENTS.md`

```markdown
# 全局规则

## 语言

- 始终使用简体中文回复用户，包括所有解释、总结、提问和代码注释说明。
- 所有内部推理/思考链（thinking/reasoning）必须全程使用简体中文；不要生成英文思考链。此要求适用于 Devin、SWE-2 及子代理、计划模式和工具调用前的推理；若模型默认倾向英文思考，必须直接改用简体中文继续推理。
- 代码本身、命令、文件路径、API 名称等技术标识符保持原文（英文），不要翻译。
- 提交信息、PR 描述等面向协作的内容，除非项目有其他约定，否则也使用中文。
```

## 变体：只汉化思考链，回复仍用英文

如果你希望**回复**保持英文、仅**思考链**用中文，把第一条删掉，改为：

```markdown
## 语言

- 始终使用英文回复用户。
- 所有内部推理/思考链（thinking/reasoning）必须全程使用简体中文，不要生成英文思考链；此要求适用于 Devin、SWE-2 及子代理、计划模式和工具调用前的推理。
- 代码、命令、文件路径、API 名称等技术标识符保持原文，不要翻译。
```

## 变体：其他语言

把"简体中文"替换为目标语言即可，例如：

- English：`All internal reasoning/thinking must be in English.`
- 日本語：`内部推論（thinking/reasoning）はすべて日本語で行うこと。`
