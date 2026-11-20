#!/usr/bin/env python3
"""check_drift.py — 可见文本语言漂移检测（离线）

用途
----
分析用户**明确提供**的可见文本（例如从 Devin 界面复制出的思考说明、
计划、回复、工具调用说明），统计其中"中文解释段落"与"英文自然语言
段落"的分布，量化语言漂移程度。

边界（重要）
------------
- 只读取用户显式传入的文本文件或 stdin，**不读取、不猜测、不接触**
  任何隐藏推理 / 内部思考链。
- 不修改任何文件，不调用网络，不依赖第三方库（仅标准库）。
- 结果是"可见文本的语言分布统计"，不代表模型内部推理的真实语言，
  也不能证明规则一定生效。

用法
----
  python check_drift.py visible.txt                 # JSON 输出
  python check_drift.py visible.txt --format csv
  python check_drift.py --compare base.json new.json  # 基线对比
  type visible.txt | python check_drift.py -        # stdin
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
from dataclasses import dataclass, field, asdict

# ---------- 预处理：剔除不应计入"自然语言"的内容 ----------

_FENCED_CODE = re.compile(r"```.*?```", re.DOTALL)
_INLINE_CODE = re.compile(r"`[^`\n]*`")
_URL = re.compile(r"https?://\S+|www\.\S+", re.IGNORECASE)
_WIN_PATH = re.compile(r"[A-Za-z]:\\[^\s，。；]+")
_UNIX_PATH = re.compile(r"(?<![\w/])/[^\s，。；]+")
# 日志行：常见级别/时间戳/进程号特征
_LOG_LINE = re.compile(
    r"^\s*(\[?\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{2}:\d{2}:\d{2}|"
    r"TRACE|DEBUG|INFO|WARN(?:ING)?|ERROR|FATAL|CRITICAL)\b",
    re.IGNORECASE,
)
# JSON / SQL 片段（整行或行内）
_JSONISH = re.compile(r'^\s*[{\[].*[}\]]\s*$')
_SQLISH = re.compile(r"\b(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP)\b.*\b(FROM|INTO|TABLE|WHERE)\b", re.IGNORECASE)

_CJK = re.compile(r"[一-鿿㐀-䶿]")
_LATIN_WORD = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)?")


def strip_non_natural(text: str) -> str:
    """移除代码块、行内代码、URL、路径、日志行、JSON/SQL 行。"""
    text = _FENCED_CODE.sub(" ", text)
    text = _INLINE_CODE.sub(" ", text)
    text = _URL.sub(" ", text)
    lines = []
    for line in text.splitlines():
        if _LOG_LINE.match(line):
            continue
        if _JSONISH.match(line) or _SQLISH.search(line):
            continue
        line = _WIN_PATH.sub(" ", line)
        line = _UNIX_PATH.sub(" ", line)
        lines.append(line)
    return "\n".join(lines)


def classify_segment(seg: str) -> str | None:
    """把一个段落/行分类为 zh / en / mixed / None(忽略)。"""
    seg = seg.strip()
    if not seg:
        return None
    cjk = len(_CJK.findall(seg))
    words = _LATIN_WORD.findall(seg)
    # 过滤疑似标识符的"单词"：驼峰、蛇形等不计入自然语言
    natural_words = [w for w in words
                     if not re.fullmatch(r"[a-z]+[A-Z][A-Za-z0-9]*|[a-z]+_[a-z0-9_]+", w)]

    if cjk == 0 and len(natural_words) >= 4:
        return "en"
    if cjk >= 2 and len(natural_words) == 0:
        return "zh"
    if cjk >= 2 and len(natural_words) >= 3:
        return "mixed"
    if cjk >= 1:
        return "zh"
    # 无中文且英文词太少 → 忽略（可能是标题、短语、标记）
    return None


@dataclass
class DriftReport:
    source: str
    total_segments: int = 0
    zh_segments: int = 0
    en_segments: int = 0
    mixed_segments: int = 0
    ignored_segments: int = 0
    drift_ratio: float = 0.0  # en / (zh + en + mixed)，0~1，越高越漂移
    en_samples: list = field(default_factory=list)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["en_samples"] = self.en_samples[:10]
        return d


def analyze(text: str, source: str = "<stdin>") -> DriftReport:
    cleaned = strip_non_natural(text)
    rep = DriftReport(source=source)
    for raw in re.split(r"\n\s*\n|\n", cleaned):
        seg = raw.strip()
        if not seg:
            continue
        rep.total_segments += 1
        kind = classify_segment(seg)
        if kind == "zh":
            rep.zh_segments += 1
        elif kind == "en":
            rep.en_segments += 1
            if len(rep.en_samples) < 10:
                rep.en_samples.append(seg[:160])
        elif kind == "mixed":
            rep.mixed_segments += 1
        else:
            rep.ignored_segments += 1
    denom = rep.zh_segments + rep.en_segments + rep.mixed_segments
    rep.drift_ratio = round(rep.en_segments / denom, 4) if denom else 0.0
    return rep


def compare(base: DriftReport, new: DriftReport) -> dict:
    return {
        "baseline": base.to_dict(),
        "upgraded": new.to_dict(),
        "delta": {
            "drift_ratio": round(new.drift_ratio - base.drift_ratio, 4),
            "en_segments": new.en_segments - base.en_segments,
            "zh_segments": new.zh_segments - base.zh_segments,
        },
        "verdict": (
            "improved" if new.drift_ratio < base.drift_ratio
            else "unchanged" if new.drift_ratio == base.drift_ratio
            else "worse"
        ),
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="可见文本语言漂移检测（离线、不读隐藏推理）")
    ap.add_argument("input", nargs="?", help="文本文件路径；'-' 或省略时读 stdin")
    ap.add_argument("--format", choices=["json", "csv"], default="json")
    ap.add_argument("--compare", nargs=2, metavar=("BASE_JSON", "NEW_JSON"),
                    help="对比两个已生成的 JSON 报告")
    ap.add_argument("--threshold", type=float, default=0.3,
                    help="drift_ratio 超过该值视为漂移明显（默认 0.3）")
    args = ap.parse_args(argv)

    if args.compare:
        base = DriftReport(**{k: v for k, v in json.load(open(args.compare[0], encoding="utf-8")).items()
                              if k in DriftReport.__dataclass_fields__})
        new = DriftReport(**{k: v for k, v in json.load(open(args.compare[1], encoding="utf-8")).items()
                             if k in DriftReport.__dataclass_fields__})
        print(json.dumps(compare(base, new), ensure_ascii=False, indent=2))
        return 0

    if args.input and args.input != "-":
        with open(args.input, encoding="utf-8", errors="replace") as f:
            text = f.read()
        source = args.input
    else:
        text = sys.stdin.read()
        source = "<stdin>"

    rep = analyze(text, source)

    if args.format == "csv":
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(["source", "total", "zh", "en", "mixed", "ignored", "drift_ratio"])
        w.writerow([rep.source, rep.total_segments, rep.zh_segments,
                    rep.en_segments, rep.mixed_segments, rep.ignored_segments,
                    rep.drift_ratio])
        sys.stdout.write(buf.getvalue())
    else:
        out = rep.to_dict()
        out["threshold"] = args.threshold
        out["flagged"] = rep.drift_ratio > args.threshold
        print(json.dumps(out, ensure_ascii=False, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
