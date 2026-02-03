# Component DCE (Dead Code Elimination) 実装計画

## 背景

WebAssembly Component Model で複数コンポーネントを合成した後、最終的なエクスポートから到達不可能なコードを削除したい。

現状のツール状況:
- **wasm-opt / wasm-metadce** (Binaryen): Core Wasm 向け、Component 非対応
- **wasm-tools**: Component 対応だが DCE 機能なし
- **wac**: 合成のみ、最適化なし

## 目標

将来的に `moon-component dce` コマンドで、composed component の未使用コードを削除する。

```bash
moon-component dce input.wasm -o output.wasm --roots "example:app/api"
```

## 現在の挙動 (2026-02-03)

- `moon-component compose --dce` で compose 後に DCE を適用できる
- この DCE は **moon-component 独自実装**（upstream の wac には未搭載）
- ルートは **exports のみ**（`--roots` は未実装）
- **コンポーネント単位（instance 単位）の削除のみ**。関数レベル DCE は未実装

### 例: examples/compose での効果測定

```bash
moon-component compose -c examples/compose/moon-component.toml
cp examples/compose/dist/composed.wasm tmp/dce-check/composed-no-dce.wasm

moon-component compose -c examples/compose/moon-component.toml --dce
cp examples/compose/dist/composed.wasm tmp/dce-check/composed-dce.wasm
```

結果:
- no dce: 81,524 bytes
- with dce: 80,726 bytes
- 差分: -798 bytes (約 -0.98%)

削除数は `0` と出るが、再エンコードによりサイズが減るケースがある。

## 実装メモ（現状）

- WAC の compose 計画上で **到達不能な instance** を削るだけ
- 依存は `export` と `...`（instance 展開）のみを追跡
- component 内部の core wasm DCE は **未対応**

## 設計

### Component Model の構造

```
Component
├── Core Module 0 (math)
│   ├── func $add
│   ├── func $multiply
│   └── func $factorial
├── Core Module 1 (strings)
│   ├── func $reverse
│   ├── func $uppercase
│   └── func $repeat
└── Core Module 2 (app) [entry]
    ├── func $calc_add      → calls Module 0.$add
    ├── func $describe_factorial → calls Module 0.$factorial, Module 1.$uppercase
    └── func $unused_helper  ← 削除対象
```

### 到達可能性分析

1. **Root の特定**
   - Component のエクスポート (world exports)
   - `--roots` オプションで指定されたインターフェース

2. **依存グラフの構築**
   ```
   export "calc-add" → Module2::calc_add → Module0::add
   export "describe-factorial" → Module2::describe_factorial
                                  ├→ Module0::factorial
                                  └→ Module1::uppercase
   ```

3. **未使用コードの特定**
   - Root から到達不可能な関数
   - 到達不可能な関数のみが参照するグローバル、メモリ、テーブル

### 削除戦略

#### Phase 1: 関数レベル DCE
- 未使用の内部関数を削除
- エクスポートされていない関数が対象
- インデックスの再マッピング

#### Phase 2: モジュールレベル DCE
- 完全に未使用のモジュールを削除
- インスタンス化の依存関係を考慮

#### Phase 3: インターフェースレベル DCE
- 未使用のインポート/エクスポートを削除
- WIT 定義との整合性を維持

## 実装ステップ（将来）

### Step 1: Component 解析 (wasmparser)

```rust
use wasmparser::{Parser, Payload};

struct ComponentAnalyzer {
    modules: Vec<ModuleInfo>,
    instances: Vec<InstanceInfo>,
    exports: Vec<ExportInfo>,
}

struct ModuleInfo {
    functions: Vec<FunctionInfo>,
    imports: Vec<ImportInfo>,
    exports: Vec<ExportInfo>,
}

fn analyze_component(bytes: &[u8]) -> Result<ComponentAnalyzer>;
```

### Step 2: 依存グラフ構築

```rust
use petgraph::graph::DiGraph;

#[derive(Hash, Eq, PartialEq)]
enum Node {
    Export(String),
    ModuleFunc { module: u32, func: u32 },
    ModuleGlobal { module: u32, global: u32 },
}

fn build_dependency_graph(analyzer: &ComponentAnalyzer) -> DiGraph<Node, ()>;
```

### Step 3: 到達可能性分析

```rust
use std::collections::HashSet;

fn find_reachable(
    graph: &DiGraph<Node, ()>,
    roots: &[Node],
) -> HashSet<Node> {
    // BFS/DFS で roots から到達可能なノードを収集
}
```

### Step 4: 未使用コード削除 (wasm-encoder)

```rust
use wasm_encoder::{Component, Module};

fn eliminate_dead_code(
    bytes: &[u8],
    reachable: &HashSet<Node>,
) -> Result<Vec<u8>> {
    // wasmparser で読みながら wasm-encoder で再構築
    // 未到達の要素をスキップ
}
```

## API 設計

### CLI

```bash
# 基本使用
moon-component dce composed.wasm -o optimized.wasm

# ルート指定
moon-component dce composed.wasm -o optimized.wasm \
  --roots "example:app/api#calc-add" \
  --roots "example:app/api#describe-factorial"

# ドライラン (削除対象を表示)
moon-component dce composed.wasm --dry-run

# 詳細出力
moon-component dce composed.wasm -o optimized.wasm -v
```

### Library API

```rust
pub struct DceOptions {
    /// 明示的なルート (指定しない場合は全エクスポート)
    pub roots: Option<Vec<String>>,
    /// 削除レベル
    pub level: DceLevel,
}

pub enum DceLevel {
    /// 関数のみ
    Functions,
    /// 関数 + グローバル + メモリ
    Full,
}

pub fn eliminate_dead_code(
    wasm_bytes: &[u8],
    options: &DceOptions,
) -> Result<Vec<u8>>;

pub fn analyze_dead_code(
    wasm_bytes: &[u8],
    options: &DceOptions,
) -> Result<DceReport>;

pub struct DceReport {
    pub total_functions: usize,
    pub reachable_functions: usize,
    pub dead_functions: Vec<DeadFunction>,
    pub estimated_size_reduction: usize,
}
```

## 依存クレート

```toml
[dependencies]
wasmparser = "0.219"      # Component 解析
wasm-encoder = "0.219"    # Component 再構築
petgraph = "0.6"          # グラフ操作
anyhow = "1.0"
```

## 制約・注意点

### 保守的な削除

- **間接呼び出し**: `call_indirect` / `call_ref` がある場合、テーブルに登録された関数は全て到達可能とみなす
- **Active segments**: data/element segment の初期化コードは常に到達可能
- **Start function**: 存在する場合は常に到達可能

### Component 固有の考慮事項

- **Aliasing**: `(alias export ...)` による参照は追跡が必要
- **Canonical ABI**: `canon lift` / `canon lower` の暗黙的な依存
- **Resource types**: drop/rep 関数の依存関係

### 段階的実装

1. まず `--dry-run` で分析のみ実装
2. 関数レベル DCE を実装
3. 検証スイートを整備
4. より積極的な最適化を追加

## 参考

- [wasm-metadce (Binaryen)](https://github.com/WebAssembly/binaryen/blob/main/src/tools/wasm-metadce.cpp)
- [wasmparser Component support](https://docs.rs/wasmparser/latest/wasmparser/)
- [Component Model spec](https://github.com/WebAssembly/component-model)
