# Compose

`moon-component compose` は **複数 component の合成**を行うメイン入口。
設定ファイル (`moon-component.toml`) を使うのが基本です。

---

## 基本形（推奨）

```bash
moon-component compose -c moon-component.toml
```

### 例: moon-component.toml

```toml
[bundle]
name = "my/app"
output = "dist/app.wasm"
entry = "apps/main/component"

[dependencies]
"example:math" = { path = "libs/math/component" }
"example:strings" = { path = "libs/strings/component" }

[build]
target = "wasm"
release = true
```

---

## prebuilt component を使う

```toml
[dependencies]
"local:regex/regex" = { component = "path/to/regex_guest.wasm" }
```

- `path` は MoonBit component のディレクトリ
- `component` は既に componentize 済みの `.wasm`

---

## オプション

```bash
# ビルドのみ（合成しない）
moon-component compose -c moon-component.toml --build-only

# ドライラン（実行せずコマンドを表示）
moon-component compose -c moon-component.toml --dry-run
```

---

## compose ファイルを直接使う

```bash
moon-component compose composition.wac -o composed.wasm
```

複雑な合成や細かな制御が必要な場合のみ使う。

---

## 処理フロー（config）

```
moon-component compose -c moon-component.toml
    │
    ├─ Phase 1: Build Dependencies
    │   └─ moon build + componentize (各依存)
    │
    ├─ Phase 2: Build Entry
    │   └─ moon build + componentize
    │
    └─ Phase 3: Compose
        └─ plug (内部処理)
```

---

## よくある落とし穴

- `world` と `interface` の同名は NG
- 依存の WIT が entry 側の import と一致している必要がある
