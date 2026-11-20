#!/usr/bin/env python3
"""check_drift.py 的离线单元测试（标准库 unittest，无需第三方依赖）。

运行: python -m unittest tests.test_check_drift -v
或:   python tests/test_check_drift.py
"""

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_drift as cd  # noqa: E402


class TestStripNonNatural(unittest.TestCase):
    def test_fenced_code_removed(self):
        text = "前文说明。\n```python\nprint('hello world foo bar')\n```\n后文说明。"
        out = cd.strip_non_natural(text)
        self.assertNotIn("print", out)
        self.assertIn("前文说明", out)
        self.assertIn("后文说明", out)

    def test_inline_code_removed(self):
        out = cd.strip_non_natural("运行 `npm install --save lodash` 完成安装。")
        self.assertNotIn("lodash", out)

    def test_url_removed(self):
        out = cd.strip_non_natural("参考 https://example.com/some/very/long/path 了解详情。")
        self.assertNotIn("example.com", out)

    def test_log_lines_removed(self):
        text = ("2024-01-01 10:00:00 INFO service started normally\n"
                "ERROR something failed badly\n"
                "这是一段正常的中文说明文字。")
        out = cd.strip_non_natural(text)
        self.assertNotIn("INFO", out)
        self.assertNotIn("ERROR", out)
        self.assertIn("中文说明", out)

    def test_json_line_removed(self):
        text = '{"key": "value", "nested": {"a": 1}}\n这是一段中文说明。'
        out = cd.strip_non_natural(text)
        self.assertNotIn('"key"', out)
        self.assertIn("中文说明", out)

    def test_windows_path_removed(self):
        out = cd.strip_non_natural("文件位于 C:\\Users\\foo\\bar\\baz.txt 中。")
        self.assertNotIn("Users", out)


class TestClassifySegment(unittest.TestCase):
    def test_chinese(self):
        self.assertEqual(cd.classify_segment("我先读取相关文件了解结构。"), "zh")

    def test_english(self):
        self.assertEqual(
            cd.classify_segment("I will now read the relevant files to understand the structure."),
            "en")

    def test_mixed(self):
        self.assertEqual(
            cd.classify_segment("我会调用 read_file 工具读取 config 文件然后分析 dependency tree。"),
            "mixed")

    def test_short_ignored(self):
        self.assertIsNone(cd.classify_segment("OK"))
        self.assertIsNone(cd.classify_segment("Step 1"))

    def test_identifier_not_counted(self):
        # 纯标识符行不应被当成英文自然语言
        self.assertIsNone(cd.classify_segment("getUserProfileById fetchDataFromServer"))


class TestAnalyze(unittest.TestCase):
    def test_all_chinese_low_drift(self):
        text = "我先查看目录结构。\n\n然后读取主入口文件。\n\n最后运行测试验证。"
        rep = cd.analyze(text)
        self.assertEqual(rep.en_segments, 0)
        self.assertEqual(rep.drift_ratio, 0.0)

    def test_english_drift_detected(self):
        text = ("I will inspect the repository structure first.\n\n"
                "Then I need to read the main entry file carefully.\n\n"
                "Finally I will run the test suite to verify everything works.")
        rep = cd.analyze(text)
        self.assertEqual(rep.en_segments, 3)
        self.assertGreater(rep.drift_ratio, 0.9)

    def test_mixed_content(self):
        text = ("我先读取配置文件 config.json。\n\n"
                "I will now analyze the dependencies and report findings.\n\n"
                "接下来运行单元测试。")
        rep = cd.analyze(text)
        self.assertGreaterEqual(rep.zh_segments, 1)
        self.assertGreaterEqual(rep.en_segments, 1)
        self.assertTrue(0 < rep.drift_ratio < 1)

    def test_code_blocks_excluded_from_drift(self):
        text = ("中文说明文字在这里。\n\n"
                "```\nThis is english inside a code block that should not count.\n```\n\n"
                "更多中文解释。")
        rep = cd.analyze(text)
        self.assertEqual(rep.en_segments, 0)


class TestCompareAndCli(unittest.TestCase):
    def test_compare_verdict(self):
        base = cd.DriftReport(source="a", zh_segments=1, en_segments=9,
                              drift_ratio=0.9)
        new = cd.DriftReport(source="b", zh_segments=9, en_segments=1,
                             drift_ratio=0.1)
        result = cd.compare(base, new)
        self.assertEqual(result["verdict"], "improved")
        self.assertLess(result["delta"]["drift_ratio"], 0)

    def test_cli_json_output(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False,
                                         encoding="utf-8") as f:
            f.write("这是一段中文说明。\n\nI will check the files now.")
            path = f.name
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = cd.main([path])
            self.assertEqual(rc, 0)
            data = json.loads(buf.getvalue())
            self.assertIn("drift_ratio", data)
            self.assertIn("en_samples", data)
        finally:
            os.unlink(path)

    def test_cli_csv_output(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False,
                                         encoding="utf-8") as f:
            f.write("纯中文内容。")
            path = f.name
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                cd.main([path, "--format", "csv"])
            self.assertIn("drift_ratio", buf.getvalue())
        finally:
            os.unlink(path)

    def test_cli_stdin(self):
        old_stdin = sys.stdin
        sys.stdin = io.StringIO("这是一段中文说明。")
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                cd.main(["-"])
            data = json.loads(buf.getvalue())
            self.assertEqual(data["source"], "<stdin>")
            self.assertEqual(data["en_segments"], 0)
        finally:
            sys.stdin = old_stdin


if __name__ == "__main__":
    unittest.main()
