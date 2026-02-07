# Rust -> MoonBit ライブラリ移植パターン

Rust ライブラリを MoonBit から使うために「Rust guest component + MoonBit host component」を作る流れをまとめます。

このドキュメントは `moon-component` 利用時の一般的な手順です。

## 1) API 設計（WIT）

- MoonBit から使いたい API を WIT に落とし込む。
- `record` は `interface` 内に置く（トップレベル定義は避ける）。
- `result<_, string>` のように unit は `_` を使う（`unit` は未対応な環境がある）。
- 数値型は codegen との相性を優先（現状 `s32` が扱いやすい）。

## 2) Rust guest component

- `cargo-component` + `wit-bindgen` で guest を生成する。
- Rust 側は「生ライブラリ -> WIT 型」への変換を担当。
- 解析ロジックは `core.rs` のように分離して Rust 単体でテストする。

## 3) MoonBit host component

- `moon-component generate` で import/export の雛形を生成。
- `impl.mbt` で import した関数を薄く呼び出すだけにする。
- 生成コード側の alias を `moon.pkg.json` に追加する（`@wasmparser` など）。

## 4) compose で統合

- `moon-component.toml` に guest wasm を依存として登録。
- `moon-component compose -c moon-component.toml` で 1 つの component に統合。

## 5) 実行確認

`wasmtime` で関数を呼び出して確認します。

```bash
wasmtime run --invoke 'validate([0,97,115,109,1,0,0,0])' dist/xxx.wasm
wasmtime run --invoke 'summarize([0,97,115,109,1,0,0,0])' dist/xxx.wasm
```

## 6) 運用時の注意

- WIT を最小化して互換性を維持する。
- Rust -> WIT 変換の境界でエラー文字列を正規化する。
- `list<u8>` はバイナリの基本手段。巨大入力はストリーム化を検討。

## 参考

- `docs/rust-port.md`
- `examples/regex/`（Rust guest + MoonBit host の実例）
