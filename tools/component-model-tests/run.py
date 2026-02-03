#!/usr/bin/env python3
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import List


DEFAULT_FLAGS = [
    "-W",
    "component-model-async=y",
    "-W",
    "component-model-async-builtins=y",
    "-W",
    "component-model-threading=y",
    "-W",
    "component-model-async-stackful=y",
    "-W",
    "exceptions=y",
]


def collect_tests(root: Path, tests: List[Path]) -> None:
    if not root.exists():
        return
    for entry in sorted(root.rglob("*.wast")):
        tests.append(entry)


def parse_flags(raw: str) -> list[str]:
    if not raw:
        return []
    return raw.strip().split()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run component-model reference tests with wasmtime"
    )
    parser.add_argument(
        "--filter",
        action="append",
        default=[],
        help="Only run tests whose path contains this string",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit number of tests to run (0 = no limit)",
    )
    parser.add_argument(
        "--flags",
        default="",
        help="Override wasmtime flags (space-separated). Default uses component-model feature flags.",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    suite = root / "tests" / "component-model"
    if not suite.exists():
        print("component-model tests not found. Run: tools/component-model-tests/update.sh", file=sys.stderr)
        return 2

    env_bin = os.environ.get("WASMTIME_BIN")
    if env_bin:
        wasmtime = env_bin
    else:
        root = Path(__file__).resolve().parents[2]
        local_bin = root / "tools" / "wasmtime" / "bin" / "wasmtime"
        alt_bin = root / "tools" / "wasmtime-main" / "bin" / "wasmtime"
        if local_bin.exists():
            wasmtime = str(local_bin)
        elif alt_bin.exists():
            wasmtime = str(alt_bin)
        else:
            wasmtime = shutil.which("wasmtime")
    if not wasmtime:
        print("wasmtime not found. Skipping component-model tests.", file=sys.stderr)
        return 2

    tests: List[Path] = []
    collect_tests(suite, tests)
    if args.filter:
        filtered = []
        for test in tests:
            path_str = str(test)
            if any(f in path_str for f in args.filter):
                filtered.append(test)
        tests = filtered

    if args.limit > 0:
        tests = tests[: args.limit]

    if not tests:
        print("No tests matched.")
        return 1

    flags = parse_flags(args.flags) if args.flags else DEFAULT_FLAGS

    failures = 0
    for test in tests:
        cmd = [wasmtime, "wast"] + flags + [str(test)]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if result.returncode != 0:
            failures += 1
            print(f"FAIL: {test}\n{result.stderr or result.stdout}")

    if failures:
        print(f"\n{failures} test(s) failed")
        return 1
    print(f"\nAll {len(tests)} test(s) passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
