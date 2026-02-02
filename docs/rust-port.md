# Rust → MoonBit Porting Workflow

Rust 実装を MoonBit に移植するための最短ワークフロー。
「Rust guest を正解系として用意し、MoonBit host から呼び出して挙動確認する」方針です。

ここでは `examples/regex` を使います。

---

## 目的

- まず Rust guest で正しい挙動を作る
- MoonBit host から Rust guest を呼び出して挙動を固定化する
- 同じ WIT を使って MoonBit guest に置き換える
- 同じ host で比較できる状態にする

---

## 1) WIT を固定する

WIT は **ホストとゲストの契約**なので最初に固める。

注意:
- `world` と `interface` の同名は NG

例 (`examples/regex/guest-rust/wit/world.wit`):

```wit
package local:regex;

interface regex {
  is-match: func(pattern: string, text: string) -> bool;
  replace: func(pattern: string, text: string, replacement: string) -> string;
}

world regex-app {
  export regex;
}
```

---

## 2) Rust guest を作る

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

---

## 3) MoonBit host を作る

ホストは `import regex` して `run` を export する。

`examples/regex/host-moonbit/wit/world.wit`:

```wit
package local:regex;

interface regex {
  is-match: func(pattern: string, text: string) -> bool;
  replace: func(pattern: string, text: string, replacement: string) -> string;
}

interface app {
  run: func(pattern: string, text: string, replacement: string) -> string;
}

world host {
  import regex;
  export app;
}
```

MoonBit 実装 (`examples/regex/host-moonbit/impl/impl.mbt`):

```mbt
///|
pub fn run(pattern : String, text : String, replacement : String) -> String {
  if @regex.is_match(pattern, text) {
    @regex.replace(pattern, text, replacement)
  } else {
    text
  }
}
```

ビルド + componentize:

```bash
cd examples/regex/host-moonbit
moon build --target wasm --release impl
moon-component componentize _build/wasm/release/build/impl/impl.wasm \
  --wit-dir wit -o host.component.wasm
```

---

## 4) Rust guest と合成して実行

```bash
cd examples/regex
mkdir -p dist
wac plug \
  --plug guest-rust/target/wasm32-wasip1/release/regex_guest.wasm \
  host-moonbit/host.component.wasm \
  -o dist/regex-app.wasm
```

```bash
wasmtime run --invoke 'run("[a-z]+", "hello 123", "X")' dist/regex-app.wasm
# => "X 123"
```

ここまでで **Rust guest の挙動が固定化**できる。

---

## 5) MoonBit guest に置き換える

同じ WIT を使って MoonBit で guest を実装し、
`wac plug` の差し替えだけで比較する。

例:
```
# Rust guest -> MoonBit guest に差し替え
wac plug \
  --plug guest-moonbit/guest.component.wasm \
  host-moonbit/host.component.wasm \
  -o dist/regex-app.moonbit.wasm
```

同じ `wasmtime run` で結果が一致すれば移植完了。

---

## Tips

- Host を MoonBit にしておくと、移植後も同じ呼び出し経路で比較できる
- `resolve-json` で WIT の解決結果を確認できる
- `wasmtime run --invoke ...` はデバッグに便利

