# hello-wite: moon-component + wite Integration Example

Demonstrates the full pipeline from WIT definition to optimized WebAssembly Component using both `moon-component` and `wite`.

## Prerequisites

- [MoonBit](https://www.moonbitlang.com/) toolchain
- [moon-component](https://github.com/example/moon-component) - WIT codegen & componentize
- [wite](https://github.com/mizchi/wite) - Wasm optimizer & analyzer
- [wasm-tools](https://github.com/bytecodealliance/wasm-tools) (optional, for verification)

## Pipeline

```
WIT definition
  ↓  moon-component generate
MoonBit bindings (gen/, impl/, stub/)
  ↓  moon build --target wasm
Core Wasm module
  ↓  moon-component componentize
Component Wasm (with WIT metadata)
  ↓  wite optimize
Optimized Component Wasm
  ↓  wite analyze
Size analysis report
```

## Quick Start

```bash
# Run the full pipeline
just all

# Or run steps individually:
just generate      # WIT → MoonBit bindings
just build         # MoonBit → core wasm
just componentize  # core → component wasm
just optimize      # wite optimization (-Oz)
just analyze       # wite size analysis
just verify        # wasm-tools WIT verification
```

## Project Structure

```
├── wit/world.wit          # WIT interface definition
├── moon.mod.json          # MoonBit module
├── wite.config.jsonc      # wite configuration
├── gen/                   # Generated bindings (moon-component generate)
│   ├── cabi/              # Canonical ABI helpers
│   └── interface/         # Export trait definitions
├── src/                   # Component entry point (re-exports)
├── stub/                  # Implementation (greet function)
└── impl/                  # Alternative impl entry point
```
