# Bundle

`moon-component bundle` は複数の MoonBit コンポーネントをビルドして `wac plug` で合成する。

## 設定

```toml
# moon-component.toml
[bundle]
name = "example/app"
output = "dist/composed.wasm"
entry = "apps/main/component"

[dependencies]
"example:math" = { path = "libs/math/component" }
"example:strings" = { path = "libs/strings/component" }

[build]
target = "wasm"
release = true
```

## 処理フロー

```
moon-component bundle
    │
    ├─ Phase 1: Build Dependencies
    │   └─ moon build + componentize (各依存)
    │
    ├─ Phase 2: Build Entry
    │   └─ moon build + componentize
    │
    └─ Phase 3: Compose
        └─ wac plug
```

## CLI

```bash
# ビルド + 合成
moon-component bundle -c moon-component.toml

# ビルドのみ（合成しない）
moon-component bundle -c moon-component.toml --build-only

# ドライラン
moon-component bundle -c moon-component.toml --dry-run
```

## 出力構造

```
_build/bundle/
├── entry.wasm
└── deps/
    └── example/
        ├── math.wasm
        └── strings.wasm
```

## 代替: justfile

bundle コマンドを使わず justfile で同じことができる:

```just
example-compose:
    moon build --target wasm --release -C libs/math/component
    moon-component componentize \
        libs/math/component/_build/wasm/release/build/impl/impl.wasm \
        -w libs/math/component/wit \
        -o _build/math.wasm

    moon build --target wasm --release -C libs/strings/component
    moon-component componentize \
        libs/strings/component/_build/wasm/release/build/impl/impl.wasm \
        -w libs/strings/component/wit \
        -o _build/strings.wasm

    moon build --target wasm --release -C apps/main/component
    moon-component componentize \
        apps/main/component/_build/wasm/release/build/impl/impl.wasm \
        -w apps/main/component/wit \
        -o _build/main.wasm

    wac plug \
        --plug _build/math.wasm \
        --plug _build/strings.wasm \
        _build/main.wasm \
        -o dist/composed.wasm
```
