#!/usr/bin/env python3
"""translate_ollama.py — 可选本地 Ollama 翻译原型（用户主动提供文本）

用途
----
把用户**自己复制出来的** Devin 可见文本（思考说明、计划、回复等）
翻译成中文对照。只处理显式传入的文件或 stdin，
与 tests/check_drift.py 同一边界：不读取隐藏推理、不接触 Devin
安装目录、不拦截网络、不注入客户端。

边界（重要）
------------
- 只允许连接本机 Ollama（默认 http://127.0.0.1:11434），拒绝远程 endpoint，
  防止文本被发送到第三方。
- 代码块、行内代码、URL、文件路径、JSON/SQL 片段、日志行原样保留。
- 翻译结果是"事后对照"，不回写 Devin，不改变模型状态。
- Ollama 未安装/未启动时可用 --mock 模式生成**明确标注的模拟译文**，
  仅用于演示与测试，绝不冒充真实翻译。

用法
----
  python translate_ollama.py visible.txt                 # 生成 visible.txt.zh.md
  python translate_ollama.py visible.txt --bilingual      # 中英对照（默认）
  python translate_ollama.py visible.txt --model qwen2.5:7b
  python translate_ollama.py visible.txt --mock           # 离线模拟（演示用）
  type visible.txt | python translate_ollama.py - --mock
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# ---------- 分段：保护不翻译的内容 ----------

_FENCED = re.compile(r"(```.*?```|~~~.*?~~~)", re.DOTALL)
_INLINE_CODE = re.compile(r"`[^`\n]+`")
_URL = re.compile(r"https?://\S+|www\.\S+", re.IGNORECASE)
_WIN_PATH = re.compile(r"[A-Za-z]:\\[^\s，。；\"')]+")
_UNIX_PATH = re.compile(r"(?<![\w/])/(?:[\w.-]+/)*[\w.-]+")
# JSON / SQL 整行
_JSONISH = re.compile(r'^\s*[{\[].*[}\]]\s*$')
_SQLISH = re.compile(r"\b(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b.*\b(FROM|INTO|TABLE|WHERE)\b", re.IGNORECASE)
_CJK = re.compile(r"[一-鿿㐀-䶿]")


def protect_segments(text: str) -> list[tuple[str, str]]:
    """把文本切成 (kind, content) 序列。

    kind: 'protected'（代码块/行内代码/路径/URL/JSON/SQL/日志行，原样保留）
          'text'（自然语言，候选翻译）
    """
    parts: list[tuple[str, str]] = []
    pos = 0
    for m in _FENCED.finditer(text):
        _emit_text_and_protected(text[pos:m.start()], parts)
        parts.append(("protected", m.group(0)))
        pos = m.end()
    _emit_text_and_protected(text[pos:], parts)
    return parts


def _emit_text_and_protected(chunk: str, parts: list) -> None:
    # 在 chunk 内再按行内代码切分
    pos = 0
    for m in _INLINE_CODE.finditer(chunk):
        _emit_plain(chunk[pos:m.start()], parts)
        parts.append(("protected", m.group(0)))
        pos = m.end()
    _emit_plain(chunk[pos:], parts)


def _emit_plain(chunk: str, parts: list) -> None:
    for line in chunk.splitlines(keepends=True):
        stripped = line.strip()
        if not stripped:
            parts.append(("text", line))
            continue
        # 先剔除行内受保护片段（URL/路径/JSON/SQL），看剩余自然语言是否足够
        residual = _URL.sub(" ", stripped)
        residual = _WIN_PATH.sub(" ", residual)
        residual = _UNIX_PATH.sub(" ", residual)
        if _JSONISH.match(stripped) or _SQLISH.search(stripped):
            parts.append(("protected", line))
            continue
        # 含中文的行不再翻译（已是中文或混合，避免重复翻译）
        if _CJK.search(stripped):
            parts.append(("protected", line))
            continue
        # 残余自然语言太少（纯路径/纯标识符行）→ 整行保护
        if len(re.findall(r"[A-Za-z]", residual)) < 4:
            parts.append(("protected", line))
            continue
        parts.append(("text", line))


def needs_translation(seg: str) -> bool:
    s = seg.strip()
    return bool(s) and not _CJK.search(s) and len(re.findall(r"[A-Za-z]", s)) >= 4


# ---------- Ollama 调用（仅 localhost） ----------

DEFAULT_ENDPOINT = "http://127.0.0.1:11434"
PROMPT_TEMPLATE = (
    "把下面的英文文本翻译成简体中文。要求：\n"
    "1. 只输出译文，不要解释、不要加引号；\n"
    "2. 代码、命令、文件路径、URL、API 名称、JSON/SQL 片段保持原文；\n"
    "3. 保持原有的换行结构。\n\n"
    "文本：\n{text}"
)


def _check_endpoint(endpoint: str) -> str:
    """只允许本机 endpoint。"""
    if not re.match(r"^https?://(127\.0\.0\.1|localhost|\[::1\])(:\d+)?/?$", endpoint):
        raise ValueError(f"仅允许本机 Ollama endpoint，拒绝: {endpoint}")
    return endpoint.rstrip("/")


def ollama_generate(endpoint: str, model: str, prompt: str,
                    timeout: int = 120, retries: int = 2) -> str:
    """调用 /api/generate，带重试。失败抛异常。"""
    base = _check_endpoint(endpoint)
    url = f"{base}/api/generate"
    payload = json.dumps({
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.2},
    }).encode("utf-8")
    last_err: Exception | None = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(
                url, data=payload,
                headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            return data.get("response", "").strip()
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last_err = e
            if attempt < retries:
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"Ollama 调用失败（已重试 {retries} 次）: {last_err}")


# ---------- 缓存 ----------

class Cache:
    def __init__(self, path: Path):
        self.path = path
        self.data: dict[str, str] = {}
        if path.exists():
            try:
                self.data = json.loads(path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                self.data = {}

    @staticmethod
    def key(text: str, model: str) -> str:
        return hashlib.sha256(f"{model}\n{text}".encode("utf-8")).hexdigest()

    def get(self, text: str, model: str) -> str | None:
        return self.data.get(self.key(text, model))

    def put(self, text: str, model: str, value: str) -> None:
        self.data[self.key(text, model)] = value

    def save(self) -> None:
        self.path.write_text(json.dumps(self.data, ensure_ascii=False, indent=1),
                             encoding="utf-8")


# ---------- 翻译主流程 ----------

def translate_text(text: str, *, endpoint: str, model: str,
                   cache: Cache, mock: bool = False) -> str:
    parts = protect_segments(text)
    out: list[str] = []
    stats = {"translated": 0, "cached": 0, "protected": 0, "failed": 0}
    for kind, seg in parts:
        if kind == "protected" or not needs_translation(seg):
            out.append(seg)
            if kind == "protected":
                stats["protected"] += 1
            continue
        # 去掉首尾空白做翻译键，保留原始边界空白
        lead = seg[: len(seg) - len(seg.lstrip())]
        trail = seg[len(seg.rstrip()):]
        core = seg.strip()

        cached = cache.get(core, model)
        if cached is not None:
            zh = cached
            stats["cached"] += 1
        elif mock:
            zh = f"[模拟译文] {core}"
            cache.put(core, model, zh)
            stats["translated"] += 1
        else:
            try:
                zh = ollama_generate(endpoint, model, PROMPT_TEMPLATE.format(text=core))
                cache.put(core, model, zh)
                stats["translated"] += 1
            except RuntimeError as e:
                print(f"[warn] 翻译失败，保留原文: {e}", file=sys.stderr)
                out.append(seg)
                stats["failed"] += 1
                continue
        out.append(f"{lead}{zh}{trail}")
    cache.save()
    return "".join(out), stats


def to_bilingual(original: str, translated: str) -> str:
    """生成中英对照 markdown：译文在前（中文阅读优先），原文引用在后。"""
    lines = ["<!-- devin-chinese-thinking:ollama-bilingual -->", ""]
    zh_lines = translated.splitlines()
    en_lines = original.splitlines()
    # 简单逐行对照；行数不一致时以译文为主
    maxlen = max(len(zh_lines), len(en_lines))
    for i in range(maxlen):
        zh = zh_lines[i] if i < len(zh_lines) else ""
        en = en_lines[i] if i < len(en_lines) else ""
        if zh:
            lines.append(zh)
        if en:
            lines.append(f"> {en}")
        lines.append("")
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="本地 Ollama 翻译原型（仅处理用户提供的文本）")
    ap.add_argument("input", nargs="?", help="文本文件；'-' 或省略读 stdin")
    ap.add_argument("--endpoint", default=DEFAULT_ENDPOINT,
                    help="Ollama 地址（仅允许 localhost，默认 %(default)s）")
    ap.add_argument("--model", default="qwen2.5:7b", help="Ollama 模型名")
    ap.add_argument("--mock", action="store_true",
                    help="离线模拟翻译（输出标注[模拟译文]，仅演示/测试用）")
    ap.add_argument("--output", "-o", help="输出文件（默认 <input>.zh.md 或 stdout）")
    ap.add_argument("--bilingual", action="store_true",
                    help="输出中英对照（默认就是对照；此参数保留兼容）")
    args = ap.parse_args(argv)

    try:
        _check_endpoint(args.endpoint)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    if args.input and args.input != "-":
        text = Path(args.input).read_text(encoding="utf-8", errors="replace")
        src_name = args.input
    else:
        text = sys.stdin.read()
        src_name = "<stdin>"

    cache_path = (Path(args.output).with_suffix(".cache.json") if args.output
                  else Path(src_name).with_suffix(".cache.json") if src_name != "<stdin>"
                  else Path("ollama-translate.cache.json"))
    cache = Cache(cache_path)

    translated, stats = translate_text(
        text, endpoint=args.endpoint, model=args.model, cache=cache,
        mock=args.mock)

    result = to_bilingual(text, translated)

    header = (f"<!-- generated by translate_ollama.py | model={args.model} | "
              f"mode={'MOCK-SIMULATED' if args.mock else 'ollama'} | "
              f"translated={stats['translated']} cached={stats['cached']} "
              f"protected={stats['protected']} failed={stats['failed']} -->\n\n")
    result = header + result

    if args.output:
        Path(args.output).write_text(result, encoding="utf-8")
        print(f"written: {args.output}  (cache: {cache_path})", file=sys.stderr)
    else:
        sys.stdout.write(result)
    print(f"stats: {stats}", file=sys.stderr)
    return 0 if stats["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
