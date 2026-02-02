# moon-component (JS build)

WebAssembly Component Model tooling for MoonBit (JavaScript build).

## Install

```bash
npm i -g @mizchi/moon-component
```

## Usage

```bash
moon-component <resolve.json|wit-path> [options]
```

Options (subset):
- `--wit <path>`: treat input as WIT file or directory
- `--resolve-json <path>`: treat input as resolve.json
- `--world <name>`: world name when resolving WIT
- `--out-dir <dir>`: output directory
- `--project-name <name>`: project name for imports
- `--gen-dir <dir>`: generated code directory (default: gen)
- `--impl-dir <dir>`: implementation directory (default: impl)
- `--no-impl`: don't generate impl files
- `--wkg`: generate wkg.toml for wa.dev deployment
- `--wkg-version <ver>`: package version (default: 0.1.0)
- `--pkg-format <fmt>`: json or dsl
- `--js-string-builtins`: enable JS String Builtins (wasm-gc only)

For native binaries, see the repository README.
