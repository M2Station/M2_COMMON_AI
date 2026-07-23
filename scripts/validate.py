#!/usr/bin/env python3
"""
驗證中央 repo 的 Copilot 設定檔結構與格式。

放置路徑：scripts/validate.py
本地執行：python scripts/validate.py
CI 執行： 由 .github/workflows/validate.yml 呼叫

檢查項目：
  1. 必要檔案存在
  2. prompt file 檔名為 <name>.prompt.md
  3. YAML frontmatter 存在、格式正確、含必要欄位
  4. description 長度合理、mode 值合法
  5. instructions file 含 applyTo
  6. copilot-instructions.md 的路由表涵蓋所有 prompt file
  7. 全檔無明顯機密字樣

退出碼：0 = 通過，1 = 有錯誤（警告不影響退出碼）
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GH = ROOT / ".github"

REQUIRED_FILES = [
    GH / "copilot-instructions.md",
]
PROMPT_DIR = GH / "prompts"
INSTRUCTION_DIR = GH / "instructions"

VALID_MODES = {"ask", "edit", "agent"}
DESC_MAX = 300

SECRET_PATTERNS = [
    (r"ghp_[A-Za-z0-9]{20,}", "GitHub personal access token"),
    (r"github_pat_[A-Za-z0-9_]{20,}", "GitHub fine-grained token"),
    (r"sk-[A-Za-z0-9]{20,}", "API secret key"),
    (r"AKIA[0-9A-Z]{16}", "AWS access key id"),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "private key"),
    (r"(?i)\b(password|passwd|api[_-]?key|secret)\s*[:=]\s*['\"][^'\"\s]{8,}['\"]", "hardcoded credential"),
]

errors: list[str] = []
warnings: list[str] = []


def err(path: Path, msg: str) -> None:
    errors.append(f"{path.relative_to(ROOT)}: {msg}")


def warn(path: Path, msg: str) -> None:
    warnings.append(f"{path.relative_to(ROOT)}: {msg}")


def parse_frontmatter(text: str) -> tuple[dict[str, str] | None, str]:
    """回傳 (frontmatter dict, 錯誤訊息)。不使用 PyYAML，只解析扁平 key: value。"""
    if not text.startswith("---"):
        return None, "缺少 YAML frontmatter（檔案必須以 --- 開頭）"

    end = re.search(r"^---\s*$", text[3:], re.MULTILINE)
    if not end:
        return None, "frontmatter 未正確關閉（缺少結尾的 ---）"

    block = text[3 : 3 + end.start()]
    data: dict[str, str] = {}
    for raw in block.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            return None, f"frontmatter 格式錯誤，無法解析：{line!r}"
        key, _, value = line.partition(":")
        data[key.strip()] = value.strip().strip("'\"")
    return data, ""


def check_secrets(path: Path, text: str) -> None:
    for pattern, label in SECRET_PATTERNS:
        m = re.search(pattern, text)
        if m:
            line_no = text[: m.start()].count("\n") + 1
            err(path, f"第 {line_no} 行疑似含有機密資訊（{label}）")


def check_prompt(path: Path) -> str | None:
    """驗證單一 prompt file，回傳其 slash command 名稱。"""
    text = path.read_text(encoding="utf-8")
    check_secrets(path, text)

    if not path.name.endswith(".prompt.md"):
        err(path, "prompt file 檔名必須以 .prompt.md 結尾")
        return None

    stem = path.name[: -len(".prompt.md")]
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", stem):
        err(path, f"檔名 {stem!r} 應為小寫，僅允許 a-z0-9 與 _ - （會直接成為 slash command 名稱）")
    if not stem.startswith("m2_"):
        warn(path, f"檔名未使用 m2_ 前綴，與組織命名慣例不一致（建議 m2_{stem}.prompt.md）")

    fm, msg = parse_frontmatter(text)
    if fm is None:
        err(path, msg)
        return stem

    if "description" not in fm:
        err(path, "frontmatter 缺少必要欄位 description")
    elif not fm["description"]:
        err(path, "description 不可為空")
    elif len(fm["description"]) > DESC_MAX:
        warn(path, f"description 過長（{len(fm['description'])} 字元，建議 <{DESC_MAX}）")

    mode = fm.get("mode") or fm.get("agent")
    if mode and mode not in VALID_MODES:
        warn(path, f"mode/agent 值 {mode!r} 非內建值（{', '.join(sorted(VALID_MODES))}），若非自訂 agent 名稱請修正")

    body = text[text.index("---", 3) + 3 :]
    if len(body.strip()) < 200:
        warn(path, "內容過短，可能不完整")
    if "硬性規則" not in body and "Hard rules" not in body:
        warn(path, "缺少「硬性規則」段落，建議補上以約束 agent 行為")

    return stem


def check_instruction(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    check_secrets(path, text)

    if not path.name.endswith(".instructions.md"):
        err(path, "instructions file 檔名必須以 .instructions.md 結尾")
        return

    fm, msg = parse_frontmatter(text)
    if fm is None:
        err(path, msg)
        return
    if "applyTo" not in fm:
        err(path, "frontmatter 缺少 applyTo，否則不會自動套用到任何檔案")


def check_powershell(path: Path) -> None:
    """Windows PowerShell 5.1 在無 BOM 時以系統 ANSI codepage 解析 .ps1。
    cp950 的 trail byte 範圍含 0x40-0x7E，UTF-8 中文位元組會被錯誤配對，
    吃掉後續引號或換行，造成敘述被當成字串、變數指派被跳過。"""
    raw = path.read_bytes()
    if not raw.startswith(b"\xef\xbb\xbf"):
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            err(path, "非 UTF-8 編碼")
            return
        if any(ord(c) > 0x2E7F for c in text):
            err(path, "含非 ASCII 字元但缺少 UTF-8 BOM —— "
                      "Windows PowerShell 5.1 會以 cp950 解析而導致亂碼與語法錯誤")


def main() -> int:
    for f in REQUIRED_FILES:
        if not f.exists():
            errors.append(f"缺少必要檔案：{f.relative_to(ROOT)}")

    for p in sorted((ROOT / "scripts").glob("*.ps1")):
        check_powershell(p)

    if not PROMPT_DIR.is_dir():
        errors.append(f"缺少目錄：{PROMPT_DIR.relative_to(ROOT)}")
        prompts: list[Path] = []
    else:
        prompts = sorted(PROMPT_DIR.glob("*.md"))
        if not prompts:
            errors.append(f"{PROMPT_DIR.relative_to(ROOT)} 內沒有任何 prompt file")

    names = [n for n in (check_prompt(p) for p in prompts) if n]

    if INSTRUCTION_DIR.is_dir():
        for p in sorted(INSTRUCTION_DIR.glob("*.md")):
            check_instruction(p)

    # 路由表涵蓋性：每支 prompt 都要能被 copilot-instructions.md 提及
    ci = GH / "copilot-instructions.md"
    if ci.exists():
        ci_text = ci.read_text(encoding="utf-8")
        check_secrets(ci, ci_text)
        for name in names:
            if f"{name}.prompt.md" not in ci_text:
                err(ci, f"路由表未涵蓋 /{name}，agent 不會知道它存在")

    print("=" * 60)
    print(f"檢查 {len(prompts)} 個 prompt file")
    print("=" * 60)

    for w in warnings:
        print(f"  WARN  {w}")
    for e in errors:
        print(f"  FAIL  {e}")

    if errors:
        print(f"\n✗ {len(errors)} 個錯誤、{len(warnings)} 個警告")
        return 1

    print(f"\n✓ 全部通過（{len(warnings)} 個警告）")
    print("  可用指令：" + "  ".join(f"/{n}" for n in names))
    return 0


if __name__ == "__main__":
    sys.exit(main())
