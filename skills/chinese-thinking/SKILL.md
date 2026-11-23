---
name: chinese-thinking
description: 强制当前会话可见输出使用简体中文（防漂移）；可附带检测可见文本的中英文占比
argument-hint: "[可选：可见文本 .txt 文件路径]"
allowed-tools:
  - exec
  - read
---

<!-- devin-chinese-thinking:v2-skill -->

执行"中文思考链防漂移"流程：

## 1. 立即重申语言规则（本会话剩余部分生效）

从现在起，本会话所有**面向用户的可见文本**一律使用简体中文，包括：

- 思考说明、分析、推理摘要（界面中可见的 Thoughts/思考部分）
- 计划（Plan 模式）、工具调用前的说明、进度汇报
- 错误解释、最终总结、向用户提问

子代理要求：本会话内派生任何 subagent 时，在其任务描述中必须
重申"可见输出使用简体中文"。

保留原文的内容：代码、命令、文件路径、URL、API 名称、SQL、JSON、
配置键值、环境变量、日志原文、堆栈中的标识符——不翻译、不音译。
代码注释默认简体中文（项目另有约定从其约定）。

## 2. 若用户提供了参数（可见文本文件路径）

检测中英文占比并如实汇报。按以下顺序尝试定位检测脚本
（仓库克隆位置因人而异，逐个探测）：

1. `%USERPROFILE%\Documents\devin-chinese-thinking\scripts\detect_language.ps1`
2. 当前工作区内 `scripts/detect_language.ps1` 或 `tests/check_drift.py`
3. 都找不到时：agent 自行对文本做粗略中英文统计（统计含中文字符的
   自然语言段 vs 纯英文自然语言段），并明确说明"为近似统计，
   未使用 check_drift.py 的完整过滤"。

找到脚本时执行：

```powershell
powershell -ExecutionPolicy Bypass -File <detect_language.ps1路径> -TextFile "<用户给的路径>"
# 或
python <check_drift.py路径> "<用户给的路径>"
```

汇报 drift_ratio 与判定（<0.1 中文为主 / ≤0.3 偶发漂移 / >0.3 漂移明显），
不夸大结论。

## 3. 边界（必须遵守）

- 只约束**可见文本**；不可见的内部推理不在本 skill 控制范围，
  不得声称已证明其语言。
- 规则是倾向性约束；若仍出现英文，直接用中文继续即可，
  不必为已输出的英文段落道歉。
- 本 skill 不读取、不修改任何 Devin 内部文件；检测仅针对用户
  显式提供的文本文件。
