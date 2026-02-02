# moon-component 入門（日本語）

MoonBit で WebAssembly Component を作るための道具一式。  
基本は **WIT → 生成 → 実装 → wasm → componentize**。

このドキュメントは「最短で動く」「迷わない」ことを優先します。

---

## 配布形態は 2 種類（機能差なし）

`moon-component` は **同じ MoonBit 実装**で、配布形態だけが 2 種類あります。
機能差はありません。

1) **npm 配布**  
   - `npx` / `npm i -g` で入れる
2) **native 配布**  
   - prebuilt かソースビルド

補足:
- `wac` は外部 CLI に依存する（`bundle / plug / compose` で必要）

---

## インストール

```bash
# Prebuilt binary (macOS/Linux)
curl -fsSL https://raw.githubusercontent.com/mizchi/moon-component/main/install.sh | bash

# wac (component compose 用)
cargo install wac-cli

# npx (no install)
npx @mizchi/moon-component

# npm
npm i -g @mizchi/moon-component
```

```bash
# Build from source (MoonBit)
moon build --target native --release -C src/main
export PATH="$PWD/_build/native/release/build/src/main:$PATH"
```

注意:
- prebuilt macOS は **arm64 のみ**。macOS x64 はソースビルド。

---

## 最短の流れ（WIT → Component）

### 0. 雛形を作る（推奨）

```bash
moon-component new my-component
cd my-component
```

この時点で WIT と実装のボイラープレートが生成されます。

### 1. WIT を用意

```wit
package demo:math;

interface math-api {
  add: func(a: u32, b: u32) -> u32;
}

world math {
  export math-api;
}
```

**ポイント**: `world` と `interface` を同名にすると WIT で弾かれます。  
（例: `world math` / `interface math` は NG）

### 2. 生成

```bash
moon-component generate wit/world.wit -o .
```

生成物のイメージ:
```
gen/   # 自動生成（触らない）
impl/  # 実装を書く
```

### 3. 実装を書く

`impl/impl.mbt` の stub を埋める:
```mbt
///|
pub fn add(a : UInt, b : UInt) -> UInt {
  a + b
}
```

### 4. ビルド（core wasm）

```bash
moon build --target wasm --release impl
```

### 5. componentize

```bash
moon-component componentize _build/wasm/release/build/impl/impl.wasm \
  --wit-dir wit -o impl.component.wasm
```

wasm-tools 直叩き:
```bash
wasm-tools component embed wit --world math _build/wasm/release/build/impl/impl.wasm -o impl.embed.wasm
wasm-tools component new impl.embed.wasm -o impl.component.wasm
```

---

## よく使うサブコマンド

- `moon-component generate <wit>`  
  WIT から MoonBit 生成
- `moon-component componentize <wasm>`  
  core wasm → component
- `moon-component component <wit>`  
  generate + build + componentize をまとめて実行
- `moon-component bundle`  
  複数 component を wac で合成（`wac` 必須）
- `moon-component plug / compose`  
  wac を使った手動合成
- `moon-component wit-from-moonbit`  
  MoonBit から WIT を生成
- `moon-component resolve-json`  
  WIT の解決結果を JSON で確認

---

## Guest / Host の 2 通り

### Guest（WIT を実装する側）

このドキュメントの最短フローがそのまま Guest 実装です。  
WIT から生成して `impl/` を埋め、componentize まで進めます。

### Host（他の WIT を使う側）

Host は **既存 component をロードして呼ぶ** / **import を実装する** 側です。

例: Rust host（wasmtime）
```bash
# Guest の export を呼ぶ
cargo run --release --manifest-path examples/host/rust/Cargo.toml -- guest \
  examples/hello/hello.component.wasm

# Import を提供する Host 側の実装
cargo run --release --manifest-path examples/host/rust/Cargo.toml -- import \
  examples/tests/import-test/import-test.component.wasm
```

Host が使う WIT は、対象 component の WIT と一致している必要があります。  
（`import-test` は `greet-provider` を **import** するので Host 側で実装する必要がある）

---

## cargo-component 連携メモ

Rust で guest を作る場合:
```bash
rustup target add wasm32-wasip1
cargo component build --release --target wasm32-wasip1
```

このコマンドは **`*.component.wasm` を出さないことがある** ので、
実際には `target/wasm32-wasip1/release/*.wasm` を component として扱うのが安定です。

Rust host（wasmtime）側で動作確認するときは:
```bash
cargo run --release --manifest-path examples/host/rust/Cargo.toml -- types \
  target/wasm32-wasip1/release/<name>.wasm
```

---

## つまづきポイント

- `cabi` の unused warnings は無視で OK（生成物の都合）
- `world` と `interface` の **同名は NG**
- `bundle/plug/compose` は **wac が必要**

---

## まとめ

- WIT は小さく始めるのが正解（まず `add` だけ動かす）

必要なら、このドキュメントを README に簡略版として移植します。
