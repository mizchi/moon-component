# moon-component 入門（日本語）

MoonBit で WebAssembly Component を作る/使うための CLI。
ここでは **Guest（MoonBit 実装側）** と **Host（任意言語で使う側）** に分けて最短で説明します。

---

## インストール

```bash
# Prebuilt binary (macOS/Linux)
curl -fsSL https://raw.githubusercontent.com/mizchi/moon-component/main/install.sh | bash

# Build from source (MoonBit)
moon build --target native --release -C src/main
export PATH="$PWD/_build/native/release/build/src/main:$PATH"
```

注意:
- prebuilt macOS は **arm64 のみ**。macOS x64 はソースビルド。

---

## Guest（MoonBit で実装する側）

### 0) 雛形を作る

```bash
moon-component new my-component
cd my-component
```

### 1) WIT を用意

`moon-component new` で生成された `wit/world.wit` を置き換える:

```wit
package demo:math;

interface math-api {
  add: func(a: u32, b: u32) -> u32;
}

world math {
  export math-api;
}
```

### 2) 生成

```bash
moon-component generate wit/world.wit -o .
```

### 3) 実装を書く

`impl/impl.mbt` の stub を埋める:
```mbt
///|
pub fn add(a : UInt, b : UInt) -> UInt {
  a + b
}
```

### 4) ビルド（core wasm）

```bash
moon build --target wasm --release impl
```

### 5) componentize

```bash
moon-component componentize _build/wasm/release/build/impl/impl.wasm \
  --wit-dir wit -o impl.component.wasm
```

### 6) wasmtime で実行

CLI っぽい component（`wasi:cli/command` を実装）ならそのまま:
```bash
wasmtime run impl.component.wasm
```

関数を直接呼びたい場合は `--invoke`（WAVE）:
```bash
wasmtime run --invoke 'add(1, 2)' impl.component.wasm
```
出力:
```
3
```

古い wasmtime では `--wasm component-model` が必要になる場合があります。

メモ:
- `world` と `interface` の **同名は NG**
- `cabi` の unused warnings は無視で OK（生成物の都合）

---

## Host（任意言語で使う側）

Host は **既存 component をロードして呼ぶ** / **import を実装する** 側です。

サンプル:
- `examples/host/rust`
- `examples/host/jco`
- `examples/host/zig`
- `examples/host/swift`
- `examples/host/scala`

Rust host（wasmtime）の例:
```bash
# Guest の export を呼ぶ
cargo run --release --manifest-path examples/host/rust/Cargo.toml -- guest \
  examples/hello/hello.component.wasm

# Import を提供する Host 側の実装
cargo run --release --manifest-path examples/host/rust/Cargo.toml -- import \
  examples/tests/import-test/import-test.component.wasm
```

ポイント:
- Host が使う WIT は、対象 component の WIT と一致している必要がある

---

必要なら README にさらに短い版を追加します。
