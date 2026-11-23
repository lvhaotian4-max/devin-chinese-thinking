# 可选兜底：本地 Ollama 翻译模块

> 状态：**原型已实现**（`scripts/translate_ollama.py`），仅处理
> 用户主动提供的文本。**原生实时集成未实现**——Devin 没有公开
> 获取已展示文本的接口，本项目不做流量解密、令牌窃取或客户端注入。

## 目标

当规则生效不完整、可见思考说明仍出现英文自然语言时，提供一个
**用户主动触发**的本地翻译通道：把用户复制出来的可见文本交给
本机 Ollama，得到中文对照译文。

## 非目标

- 不读取 Devin 的隐藏推理 / 内部思考链
- 不自动抓取 Devin 界面内容（不依赖 DOM、CDP、UI Automation）
- 不修改 Devin 安装目录或其进程
- 不在网络层做拦截/改写
- 不把翻译结果回写进 Devin 会话

## 用法

```bash
# 离线演示（模拟译文，标注 [模拟译文]，不需要 Ollama）
python scripts/translate_ollama.py visible.txt --mock

# 真实翻译（需要本机 Ollama 运行，默认 http://127.0.0.1:11434）
python scripts/translate_ollama.py visible.txt --model qwen2.5:7b

# stdin 输入
cat visible.txt | python scripts/translate_ollama.py - --mock
```

输出为 `<input>.zh.md`：中文译文在前、英文原文引用在后（中英对照），
文件头标注 model / 模式 / 统计信息。缓存保存在 `<input>.cache.json`，
重复文本自动去重（sha256 键），失败自动重试 2 次。

## 保护措施（已实现）

1. **只处理用户显式提供的文件/stdin**，与 `check_drift.py` 同一边界。
2. endpoint 白名单：仅允许 `127.0.0.1` / `localhost` / `[::1]`，
   远程地址直接拒绝，防止文本外发。
3. 分段保护： fenced 代码块、行内代码、URL、Windows/Unix 路径、
   JSON/SQL 行、含中文的行一律原样保留不翻译。
4. 翻译 prompt 明确要求只输出译文、技术标识符保持原文。
5. 失败的段落保留英文原文并在 stderr 告警，不产生半成品误导。
6. `--mock` 模式输出 `[模拟译文]` 前缀，**绝不冒充真实翻译**，
   仅用于演示与测试。

## 与规则/hook 的关系

- 规则文件与 hook 是第一道防线：让模型直接用中文生成可见文本。
- Ollama 翻译是第二道：只对**已经产生**的英文可见文本做事后对照，
  不声称能改变模型内部状态。
- 三者可独立使用；卸载规则/hook 不影响翻译脚本，反之亦然。
- Ollama **不是**原有规则配置模式的依赖：不配置、不安装也完全不影响
  install/status/uninstall/test 各脚本。

## 未实现（明确声明）

- 原生实时集成：自动获取 Devin 界面已展示文本并即时翻译。
  阻塞原因：Devin 未公开此类接口；实现需要 DOM/CDP/UIA 抓取或
  流量层操作，均超出"用户主动导出"的授权边界，本项目不做。
