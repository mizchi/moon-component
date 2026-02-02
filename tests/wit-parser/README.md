# WIT Parser Standard Test Suite

This directory hosts the upstream WIT parser tests from
`bytecodealliance/wasm-tools` (`crates/wit-parser/tests/ui`).

The tests are **not** committed to this repo. Use the scripts under
`tools/wit-tests/` to fetch and run them locally.

## Update the test suite

```bash
./tools/wit-tests/update.sh
```

You can pin a specific ref with:

```bash
WIT_TESTS_REF=<branch-or-commit> ./tools/wit-tests/update.sh
```

## Run the tests

```bash
./tools/wit-tests/run.py
```

Notes:
- The runner compares `resolve-json` output (from `tools/moon-component`) with
  upstream `*.wit.json` expectations.
- `parse-fail` cases are verified as **failing** by default. Use
  `--strict-errors` to compare error text to `*.wit.result`.
- The runner enables the WIT feature gate `active` by default via the
  `MOON_COMPONENT_WIT_FEATURES` environment variable.
