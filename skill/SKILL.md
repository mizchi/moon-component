---
name: moon-component
description: Project-specific workflow for mizchi/moon-component (MoonBit CLI + release flow).
---

# moon-component Skill

Use this skill when working in this repository. It captures project conventions and the current release workflow.

## Project Structure

- MoonBit module root: `moon.mod.json`
- Packages are per directory with `moon.pkg.json`
- CLI entry: `src/main/main.mbt`
- Rust wrapper CLI: `tools/moon-component`
- Examples live under `examples/`
- Docs live under `docs/`

## Coding Conventions

- MoonBit code uses block separators `///|`
- Prefer adding deprecated blocks to `deprecated.mbt` in each package
- Keep file names descriptive and cohesive

## Common Commands

```bash
# Format + update interface summaries
moon info
moon fmt

# Tests
moon test

# Build MoonBit CLI
moon build --target native --release -C src/main

# Build JS CLI assets
./tools/npm/build.sh

# Package prebuilt binaries
./tools/dist/package.sh <os> <arch>
```

## Release Workflow (just)

Local release (version bump + format + npm build + commit + tag):

```bash
just release-local 0.1.2
```

CI artifact build only:

```bash
just release-ci macos arm64
just release-ci linux x64
```

Notes:
- `release-local` updates `moon.mod.json` version and creates `vX.Y.Z` tag
- CI release is handled by `.github/workflows/release.yml`

## Examples

- `examples/regex` demonstrates Rust guest + MoonBit host composition
- Host language examples live under `examples/host/*`

## Gotchas

- `cabi` unused warnings are expected in generated code
- `world` and `interface` must not share the same name in WIT
