# WASI CLI (Preview2) Example

`wasi:cli/command@0.2.9` を include する最小の component 例。

- **Guest**: MoonBit
- **World**: WASI Preview2 CLI (`wasi:cli/command`)
- **目的**: `wasi:cli/run` の `run()` を実装して componentize する

## Files

- `wit/world.wit`: WASI CLI world
- `wit/deps/`: 依存 WIT (wasi:cli / wasi:io / wasi:clocks / wasi:filesystem / wasi:sockets / wasi:random)
- `impl/impl.mbt`: `run()` の実装

## Build

```bash
# 1) Generate (already generated, but re-run is OK)
moon-component generate wit/world.wit -o .

# 2) Build (impl package)
moon build --target wasm --release impl

# 3) Componentize
moon-component componentize _build/wasm/release/build/impl/impl.wasm \
  --wit-dir wit -o component.wasm
```

## Run (wasmtime)

```bash
wasmtime run component.wasm
```

`run()` は `wasi:cli/environment.get-arguments` を呼び、引数があると `Ok(())` を返します。

```bash
# 引数なし: Err(()) -> exit code 1
wasmtime run component.wasm
echo $?

# 引数あり: Ok(()) -> exit code 0
wasmtime run component.wasm -- ok
echo $?
```
