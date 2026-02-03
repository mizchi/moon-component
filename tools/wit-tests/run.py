#!/usr/bin/env python3
import argparse
import difflib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import List


def collect_tests(root: Path, tests: List[Path]) -> None:
    if not root.exists():
        return
    for entry in sorted(root.iterdir()):
        if entry.name == "parse-fail":
            continue
        if entry.is_dir():
            tests.append(entry)
            continue
        if entry.suffix in {".md", ".wit", ".wat", ".wasm"}:
            tests.append(entry)


def expected_path(test: Path, extension: str) -> Path:
    # Mirror wasm-tools wit-parser test runner behavior.
    # For non-md files and directories, it always uses ".wit.<ext>".
    if test.suffix == ".md" and test.stem.endswith(".wit"):
        return test.with_suffix(f".md.{extension}")
    return test.with_suffix(f".wit.{extension}")


def normalize(text: str, extension: str) -> str:
    text = text.strip()
    if extension == "result":
        return text.replace("\\", "/").replace("\r\n", "\n")
    return text.replace("\r\n", "\n")


def normalize_json_value(value):
    if isinstance(value, dict):
        normalized = {}
        for key, val in value.items():
            if key == "fixed-size-list":
                key = "fixed-length-list"
            normalized[key] = normalize_json_value(val)
        return normalized
    if isinstance(value, list):
        return [normalize_json_value(item) for item in value]
    return value


def detect_runner(root: Path) -> list[str] | None:
    env_bin = os.environ.get("MOON_COMPONENT_BIN")
    if env_bin:
        return [env_bin]
    path_bin = shutil.which("moon-component")
    if path_bin:
        return [path_bin]
    debug_bin = root / "tools" / "moon-component" / "target" / "debug" / "moon-component"
    if debug_bin.exists():
        return [str(debug_bin)]
    release_bin = root / "tools" / "moon-component" / "target" / "release" / "moon-component"
    if release_bin.exists():
        return [str(release_bin)]
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Run wit-parser standard tests against moon-component")
    parser.add_argument("--features", default="active", help="Comma-separated WIT features to enable")
    parser.add_argument("--strict-errors", action="store_true", help="Compare parse-fail errors with .result files")
    parser.add_argument("--filter", action="append", default=[], help="Only run tests whose path contains this string")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    suite = root / "tests" / "wit-parser" / "ui"
    if not suite.exists():
        print("wit-parser tests not found. Run: tools/wit-tests/update.sh", file=sys.stderr)
        return 2

    tests: List[Path] = []
    collect_tests(suite, tests)
    collect_tests(suite / "parse-fail", tests)
    tests = sorted(tests)

    if args.filter:
        filtered = []
        for test in tests:
            path_str = str(test)
            if any(f in path_str for f in args.filter):
                filtered.append(test)
        tests = filtered

    runner = detect_runner(root)
    if runner is None:
        print(
            "moon-component binary not found. Install from npm/prebuilt or set MOON_COMPONENT_BIN.",
            file=sys.stderr,
        )
        return 2
    env = os.environ.copy()
    if args.features:
        env["MOON_COMPONENT_WIT_FEATURES"] = args.features

    failures = 0
    for test in tests:
        is_parse_fail = "parse-fail" in test.parts
        cmd = runner + ["resolve-json", str(test)]
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            cwd=root,
        )

        if is_parse_fail:
            if result.returncode == 0:
                print(f"FAIL (expected parse error): {test}")
                failures += 1
                continue
            if args.strict_errors:
                expected_file = expected_path(test, "result")
                try:
                    expected = expected_file.read_text()
                except FileNotFoundError:
                    print(f"FAIL (missing expected file): {expected_file}")
                    failures += 1
                    continue
                expected_norm = normalize(expected, "result")
                actual_norm = normalize(result.stderr or result.stdout, "result")
                if expected_norm != actual_norm:
                    diff = "\n".join(
                        difflib.unified_diff(
                            expected_norm.splitlines(),
                            actual_norm.splitlines(),
                            fromfile="expected",
                            tofile="actual",
                            lineterm="",
                        )
                    )
                    print(f"FAIL (error mismatch): {test}\n{diff}")
                    failures += 1
            continue

        if result.returncode != 0:
            print(f"FAIL (parse error): {test}\n{result.stderr}")
            failures += 1
            continue

        expected_file = expected_path(test, "json")
        try:
            expected_json = json.loads(expected_file.read_text())
        except FileNotFoundError:
            print(f"FAIL (missing expected file): {expected_file}")
            failures += 1
            continue

        try:
            actual_json = json.loads(result.stdout)
        except json.JSONDecodeError as e:
            print(f"FAIL (invalid JSON output): {test}\n{e}\n{result.stdout}")
            failures += 1
            continue

        if isinstance(actual_json, dict) and "resolve" in actual_json:
            actual_json = actual_json["resolve"]

        expected_json = normalize_json_value(expected_json)
        actual_json = normalize_json_value(actual_json)

        if expected_json != actual_json:
            expected_dump = json.dumps(expected_json, indent=2, sort_keys=True)
            actual_dump = json.dumps(actual_json, indent=2, sort_keys=True)
            diff = "\n".join(
                difflib.unified_diff(
                    expected_dump.splitlines(),
                    actual_dump.splitlines(),
                    fromfile="expected",
                    tofile="actual",
                    lineterm="",
                )
            )
            print(f"FAIL (json mismatch): {test}\n{diff}")
            failures += 1

    if failures:
        print(f"\n{failures} test(s) failed")
        return 1
    print(f"\nAll {len(tests)} test(s) passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
