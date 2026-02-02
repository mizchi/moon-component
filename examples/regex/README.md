# Rust guest + MoonBit host (regex)

Rust の `regex` を使った component を MoonBit 側から呼び出す例。
ホスト側は MoonBit で `regex` インターフェースを import し、`run` を export します。

## 1) Rust guest をビルド

```bash
cd examples/regex/guest-rust
rustup target add wasm32-wasip1
cargo install cargo-component
cargo component build --release --target wasm32-wasip1
```

出力:
```
examples/regex/guest-rust/target/wasm32-wasip1/release/regex_guest.wasm
```

## 2) MoonBit host をビルド

```bash
cd examples/regex/host-moonbit
moon build --target wasm --release impl
moon-component componentize _build/wasm/release/build/impl/impl.wasm \
  --wit-dir wit -o host.component.wasm
```

## 3) 合成 (wac)

```bash
cd examples/regex
mkdir -p dist
wac plug \
  --plug guest-rust/target/wasm32-wasip1/release/regex_guest.wasm \
  host-moonbit/host.component.wasm \
  -o dist/regex-app.wasm
```

## 4) 実行 (wasmtime)

```bash
wasmtime run --invoke 'run("[a-z]+", "hello 123", "X")' dist/regex-app.wasm
# => "X 123"
```

## 何をやっているか

- Rust guest: `local:regex/regex` を export
- MoonBit host: `local:regex/regex` を import して `run` を export
- `wac plug` で host に guest を差し込み、1つの component に合成
