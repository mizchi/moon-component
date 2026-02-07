# Spin WAGI (WASIp2) Example

Spin HTTP trigger に **WAGI executor** を組み合わせ、
MoonBit 製の `wasi:cli/run@0.2.9` component を動かす最小例です。

- **Guest**: MoonBit
- **World**: `wasi:cli/command@0.2.9`
- **Spin trigger**: `http`
- **Executor**: `wagi`

`run()` は stdout に WAGI 形式の HTTP レスポンスを出力します。

## Files

- `wit/world.wit`: WASIp2 CLI world
- `impl/impl.mbt`: `run()` 実装
- `spin.toml`: Spin マニフェスト

## Build

```bash
moon build --target wasm --release impl
moon-component componentize _build/wasm/release/build/impl/impl.wasm \
  --wit-dir wit -o component.wasm
```

## Quick Check (wasmtime)

```bash
wasmtime run component.wasm
```

期待される出力:

```text
Content-Type: text/plain
Status: 200

hello from moon-component (WASIp2 + WAGI)
```

## Run on Spin

```bash
# examples/spin-wagi で
spin up
```

別ターミナルで:

```bash
curl -i http://127.0.0.1:3000/
```

`200 OK` と `hello from moon-component (WASIp2 + WAGI)` が返れば成功です。

## Notes

- この例は **WASIp2 component** を Spin に組み込むための最小構成です。
- `wasi:http/incoming-handler` 直実装ではなく、`wagi` 経由で HTTP 応答を返します。
