#!/usr/bin/env python3
"""Run MoonSpell against the Hunspell fixture suite."""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import subprocess
import sys
from pathlib import Path


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
    )


def find_binary(root: Path) -> Path | None:
    candidates = [
        root / "_build/native/release/build/cmd/main/main.exe",
        root / "_build/native/release/build/cmd/main/main",
        root / "_build/native/debug/build/cmd/main/main.exe",
        root / "_build/native/debug/build/cmd/main/main",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return None


def ensure_binary(root: Path, explicit: Path | None) -> Path:
    if explicit is not None:
        if not explicit.exists():
            raise FileNotFoundError(f"MoonSpell binary not found: {explicit}")
        return explicit
    binary = find_binary(root)
    if binary is not None:
        return binary
    process = run(["moon", "build", "--target", "native", "--release"], root)
    if process.returncode != 0:
        raise RuntimeError(
            "moon build failed:\n" + process.stdout + "\n" + process.stderr
        )
    binary = find_binary(root)
    if binary is None:
        raise FileNotFoundError("MoonSpell native binary was not produced")
    return binary


def nonempty_lines(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
        if line.strip()
    ]


def run_check(binary: Path, root: Path, aff: Path, dic: Path, words: Path) -> dict:
    process = run(
        [str(binary), "check-file", str(aff), str(dic), str(words)],
        root,
    )
    actual: list[str] = []
    for line in process.stdout.splitlines():
        if "\t" not in line:
            continue
        word, status = line.rsplit("\t", 1)
        actual.append(f"{word}\t{status}")
    return {"returncode": process.returncode, "actual": actual, "stderr": process.stderr}


def check_fixture(
    binary: Path,
    root: Path,
    aff: Path,
    dic: Path,
    fixture: str,
    suffix: str,
    expect: str,
) -> dict:
    words_path = aff.parent / f"{fixture}.{suffix}"
    if not words_path.exists():
        return {"present": False}
    expected_words = nonempty_lines(words_path)
    process = run_check(binary, root, aff, dic, words_path)
    statuses: dict[str, str] = {}
    for line in process["actual"]:
        word, status = line.rsplit("\t", 1)
        statuses[word] = status
    mismatches = []
    for word in expected_words:
        actual = statuses.get(word, "missing")
        if actual != expect:
            mismatches.append({"word": word, "expected": expect, "actual": actual})
    passed = process["returncode"] == 0 and not mismatches
    return {
        "present": True,
        "passed": passed,
        "expected_count": len(expected_words),
        "matched_count": len(expected_words) - len(mismatches),
        "mismatches": mismatches[:25],
        "stderr": process["stderr"].strip(),
    }


def parse_suggestions(stdout: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for line in stdout.splitlines():
        if "\t" not in line:
            continue
        word, raw = line.split("\t", 1)
        suggestions = [item.strip() for item in raw.split(",") if item.strip()]
        result[word] = suggestions
    return result


def suggestion_fixture(
    binary: Path,
    root: Path,
    aff: Path,
    dic: Path,
    fixture: str,
    suggestion_limit: int,
) -> dict:
    wrong_path = aff.parent / f"{fixture}.wrong"
    expected_path = aff.parent / f"{fixture}.sug"
    if not wrong_path.exists() or not expected_path.exists():
        return {"present": False}
    wrong_words = nonempty_lines(wrong_path)
    expected_lines = nonempty_lines(expected_path)
    process = run(
        [
            str(binary),
            "suggest-file",
            str(aff),
            str(dic),
            str(wrong_path),
            "--limit",
            str(suggestion_limit),
        ],
        root,
    )
    actual = parse_suggestions(process.stdout)
    exact = 0
    top1 = 0
    details = []
    expected_index = 0
    for word in wrong_words:
        got = actual.get(word, [])
        # Hunspell's -a mode emits suggestion lines only for misspelled words
        # that produced a suggestion. Preserve that mapping for fixtures with
        # unsuggestable entries instead of pairing every .wrong line blindly.
        if not got:
            continue
        has_expected = expected_index < len(expected_lines)
        if has_expected:
            expected = expected_lines[expected_index]
            expected_index += 1
            expected_items = [item.strip() for item in expected.split(",") if item.strip()]
        else:
            expected_items = []
        expected_text = ", ".join(expected_items)
        actual_text = ", ".join(got[: len(expected_items)])
        is_exact = has_expected and expected_items and actual_text == expected_text
        is_top1 = has_expected and bool(expected_items and expected_items[0] in got)
        if is_exact:
            exact += 1
        if is_top1:
            top1 += 1
        details.append(
            {
                "word": word,
                "expected": expected_items,
                "actual": got,
                "exact": is_exact,
                "top1": is_top1,
            }
        )
    total = len(expected_lines)
    return {
        "present": True,
        "total": total,
        "exact": exact,
        "top1": top1,
        "details": details[:25],
        "stderr": process.stderr.strip(),
    }


def selected(fixture: str, filters: list[str]) -> bool:
    return not filters or any(fnmatch.fnmatch(fixture, item) for item in filters)


def markdown_report(data: dict, rows: list[dict]) -> str:
    summary = data["summary"]
    lines = [
        "# MoonSpell Hunspell Conformance Report",
        "",
        f"- Hunspell reference: `{data['reference']}`",
        f"- Fixtures scanned: `{summary['fixtures']}`",
        f"- Good-word fixtures passed: `{summary['good_passed']}/{summary['good_total']}`",
        f"- Wrong-word fixtures passed: `{summary['wrong_passed']}/{summary['wrong_total']}`",
        f"- Suggestion fixtures: `{summary['suggestion_total']}`",
        f"- Suggestion top-1 hits: `{summary['suggestion_top1']}/{summary['suggestion_cases']}`",
        f"- Suggestion exact-list matches: `{summary['suggestion_exact']}/{summary['suggestion_cases']}`",
        "",
        "| Fixture | Good | Wrong | Suggest exact | Suggest top-1 |",
        "|---|---:|---:|---:|---:|",
    ]
    for row in rows:
        good = row.get("good", {})
        wrong = row.get("wrong", {})
        suggestion = row.get("suggestion", {})
        good_text = "skip" if not good.get("present") else ("pass" if good.get("passed") else "fail")
        wrong_text = "skip" if not wrong.get("present") else ("pass" if wrong.get("passed") else "fail")
        exact_text = "-" if not suggestion.get("present") else f"{suggestion['exact']}/{suggestion['total']}"
        top1_text = "-" if not suggestion.get("present") else f"{suggestion['top1']}/{suggestion['total']}"
        lines.append(f"| `{row['fixture']}` | {good_text} | {wrong_text} | {exact_text} | {top1_text} |")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--filter", action="append", default=[])
    parser.add_argument("--limit-fixtures", type=int)
    parser.add_argument("--suggestion-limit", type=int, default=10)
    parser.add_argument("--report", type=Path, default=Path("conformance-report.md"))
    parser.add_argument("--json", type=Path, default=Path("conformance-report.json"))
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    root = args.root.resolve()
    binary = ensure_binary(root, args.binary.resolve() if args.binary else None)
    dictionaries = sorted(args.suite.glob("*.dic"))
    if args.limit_fixtures is not None:
        dictionaries = dictionaries[: args.limit_fixtures]

    rows = []
    summary = {
        "fixtures": 0,
        "good_total": 0,
        "good_passed": 0,
        "wrong_total": 0,
        "wrong_passed": 0,
        "suggestion_total": 0,
        "suggestion_cases": 0,
        "suggestion_top1": 0,
        "suggestion_exact": 0,
    }

    for dic in dictionaries:
        fixture = dic.stem
        if not selected(fixture, args.filter):
            continue
        aff = dic.with_suffix(".aff")
        if not aff.exists():
            continue
        summary["fixtures"] += 1
        good = check_fixture(binary, root, aff, dic, fixture, "good", "accepted")
        wrong = check_fixture(binary, root, aff, dic, fixture, "wrong", "rejected")
        suggestion = suggestion_fixture(
            binary, root, aff, dic, fixture, args.suggestion_limit
        )
        if good.get("present"):
            summary["good_total"] += 1
            summary["good_passed"] += int(bool(good.get("passed")))
        if wrong.get("present"):
            summary["wrong_total"] += 1
            summary["wrong_passed"] += int(bool(wrong.get("passed")))
        if suggestion.get("present"):
            summary["suggestion_total"] += 1
            summary["suggestion_cases"] += suggestion["total"]
            summary["suggestion_top1"] += suggestion["top1"]
            summary["suggestion_exact"] += suggestion["exact"]
        row = {
            "fixture": fixture,
            "good": good,
            "wrong": wrong,
            "suggestion": suggestion,
        }
        rows.append(row)
        print(
            f"{fixture}: good={good.get('passed', 'skip')} "
            f"wrong={wrong.get('passed', 'skip')} "
            f"suggest={suggestion.get('top1', '-')}/{suggestion.get('total', '-')}"
        )

    data = {
        "reference": "hunspell-1.7.3",
        "suite": str(args.suite.resolve()),
        "summary": summary,
        "fixtures": rows,
    }
    args.report.write_text(markdown_report(data, rows), encoding="utf-8")
    args.json.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if args.strict:
        all_good = summary["good_passed"] == summary["good_total"]
        all_wrong = summary["wrong_passed"] == summary["wrong_total"]
        return 0 if all_good and all_wrong else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())