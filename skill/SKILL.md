---
name: moon-component
description: How to use the moon-component CLI (MoonBit WIT/component workflow).
---

# moon-component Skill

Use this skill when you need to **use the moon-component CLI** to build or compose WebAssembly Components from WIT + MoonBit.

## Common Commands (CLI)

```bash
# Generate MoonBit bindings from WIT
moon-component generate wit/world.wit -o .

# Build core wasm (MoonBit)
moon build --target wasm --release impl

# Componentize core wasm
moon-component componentize _build/wasm/release/build/impl/impl.wasm \
  --wit-dir wit -o impl.component.wasm

# Full workflow (generate + build + componentize)
moon-component component wit/world.wit -o impl.component.wasm --release
```

## Compose Components

```bash
# Use a config file (default entry)
moon-component compose -c moon-component.toml
```

## Guest / Host

- **Guest**: WIT 実装側。`generate` で `impl/` を生成して実装し、`componentize` する。
- **Host**: component を呼ぶ側。必要なら `wac plug` で合成してから実行。

## Examples

- `examples/regex` (Rust guest + MoonBit host)
- `examples/hello` (最小の export)
- `examples/host/*` (他言語 host)

## Gotchas

- `cabi` unused warnings are expected in generated code
- `world` and `interface` must not share the same name in WIT
