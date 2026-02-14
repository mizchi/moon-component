# Componentize: Core Wasm → Component Wasm

MoonBit ライブラリを WebAssembly Component に変換するためのワークフロー。

## 概要

`moon-component componentize` は MoonBit が出力する core wasm モジュールを [WebAssembly Component Model](https://component-model.bytecodealliance.org/) 準拠のコンポーネントに変換します。

内部では以下を実行します：

1. retptr（return pointer）パターンの検出と WAT パッチ
2. `wasm-tools component embed` で WIT メタデータを埋め込み
3. `wasm-tools component new` でコンポーネント化

## 前提条件

- [MoonBit](https://www.moonbitlang.com/) toolchain
- [moon-component](https://github.com/mizchi/moon-component) CLI
- [wasm-tools](https://github.com/bytecodealliance/wasm-tools) (`component embed` / `component new` に必要)
- [jco](https://github.com/nicolo-ribaudo/jco)（JS テスト用、optional）

```bash
# wasm-tools (cargo)
cargo install wasm-tools

# jco (npm)
npm install -g @bytecodealliance/jco
```

## ワークフロー

```
WIT 定義 (world.wit)
    │
    ▼
moon-component generate <wit-path> --out-dir . --no-impl
    │  gen/cabi/cabi.mbt           (CABI ヘルパー)
    │  gen/cabi/moon.pkg.json
    │  impl/bindings.mbt           (wasmExport ラッパー)
    │  impl/moon.pkg.json          (link exports 設定)
    │  impl/impl.mbt               (スタブ、初回のみ)
    ▼
impl.mbt を手動実装
    │
    ▼
moon build --target wasm --release
    │  _build/wasm/release/build/impl/impl.wasm (core wasm)
    ▼
moon-component componentize <core.wasm> --wit-dir <wit-dir> -o <output.wasm>
    │  retptr パッチ（必要な場合のみ自動適用）
    │  wasm-tools component embed + new
    ▼
output.component.wasm (WebAssembly Component)
    │
    ▼  (optional)
jco transpile → JS テスト / wasmtime --invoke
```

## ディレクトリ構成テンプレート

```
component/
├── moon.mod.json           # deps: { "ns/lib": { "path": ".." } }
├── wit/
│   └── world.wit           # WIT インターフェース定義
├── gen/                    # 自動生成 (moon-component)
│   └── cabi/
│       ├── cabi.mbt        # Canonical ABI ヘルパー
│       └── moon.pkg.json
├── impl/
│   ├── moon.pkg.json       # is-main, exports, link 設定
│   ├── bindings.mbt        # 自動生成（wasmExport ラッパー）
│   └── impl.mbt            # 手動実装
├── justfile
└── test/
    └── test.mjs            # jco transpile 後の E2E テスト
```

### moon.mod.json

ライブラリを path 依存で参照：

```json
{
  "name": "my-component",
  "version": "0.1.0",
  "deps": {
    "ns/lib": { "path": ".." }
  },
  "source": "."
}
```

### impl/moon.pkg.json

`is-main: true` にし、wasm/wasm-gc 両方の link exports を設定：

```json
{
  "is-main": true,
  "import": [
    { "path": "my-component/gen/cabi", "alias": "cabi" }
  ],
  "link": {
    "wasm": {
      "exports": [
        "cabi_realloc:cabi_realloc",
        "wasmExportMyFunc:ns:pkg/interface@version#my-func"
      ],
      "export-memory-name": "memory"
    },
    "wasm-gc": {
      "exports": [
        "cabi_realloc:cabi_realloc",
        "wasmExportMyFunc:ns:pkg/interface@version#my-func"
      ],
      "export-memory-name": "memory"
    }
  }
}
```

export の形式: `moonbitFuncName:wit-namespace:wit-package/wit-interface@version#wit-func-name`

## justfile テンプレート

### Export-only パターン

import なし、export のみのシンプルなケース。

```just
moon_component := env("MOON_COMPONENT", "moon-component")
wasm := "_build/wasm/release/build/impl/impl.wasm"
out := "my-component.wasm"

default:
    @just --list

generate:
    cd {{justfile_directory()}} && {{moon_component}} generate wit --out-dir . --no-impl

build-wasm:
    cd {{justfile_directory()}} && moon build --target wasm --release

build: build-wasm
    cd {{justfile_directory()}} && {{moon_component}} componentize {{wasm}} --wit-dir wit -o {{out}}

transpile: build
    npx jco transpile {{out}} -o test/gen

test: transpile
    node test/test.mjs

wit: build
    wasm-tools component wit {{out}}

clean:
    rm -rf _build {{out}} test/gen
```

### Import + Export パターン

外部インターフェースを import するケース。WIT deps のフェッチが追加される。

```just
moon_component := env("MOON_COMPONENT", "moon-component")
wasm := "_build/wasm/release/build/impl/impl.wasm"
out := "my-component.wasm"

default:
    @just --list

fetch:
    cd {{justfile_directory()}} && {{moon_component}} fetch --from-wit wit/world.wit --wit-dir wit

generate:
    cd {{justfile_directory()}} && {{moon_component}} generate wit --out-dir . --no-impl

build-wasm:
    cd {{justfile_directory()}} && moon build --target wasm --release

build: build-wasm
    cd {{justfile_directory()}} && {{moon_component}} componentize {{wasm}} --wit-dir wit -o {{out}}

transpile: build
    npx jco transpile {{out}} -o test/gen

test: transpile
    node test/test.mjs

clean:
    rm -rf _build {{out}} test/gen
```

## retptr パッチ

### 問題

MoonBit の wasm ターゲットは、複合型（string, list, record 等）を返す関数に対して "return pointer" パターンを使います。
コンパイラが `(import "..." "..." (func (type N)))` の形式で import を生成し、対応する type が `(func (param ...) (result i32))` になります。

しかし Component Model の Canonical ABI では、retptr を使う関数のシグネチャは `(param ... i32)` (最後のパラメータが retptr) で result がありません。

### 自動パッチ

`moon-component componentize` はこの不一致を自動検出し、WAT レベルでパッチを適用します：

1. `wasm-tools print` で WAT に変換
2. retptr import の `(type N)` 参照をインライン化し、`(result i32)` を除去
3. 対応する `call` の後の `drop` 命令を除去
4. `wasm-tools parse` で wasm に戻す
5. 通常の embed + new を実行

retptr が不要な場合（プリミティブ型のみの export）は、パッチなしで直接 embed + new を実行します。

## 参考例

| 例 | パターン | 説明 |
|---|---|---|
| `examples/hello/` | export-only | 最小限の string → string エクスポート |
| `examples/demo-math/` | export-only | 数値演算のエクスポート |
| `examples/regex/` | import + export + compose | Rust guest + MoonBit host の組み合わせ |
| `examples/tests/import-test/` | import + export | import を使うコンポーネント |
| `examples/compose/` | composition | 複数コンポーネントの WAC 合成 |
