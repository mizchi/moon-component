# Spin + Moon Component + Mars Router Split Example

`mizchi/mars.mbt` の `router` / `router/trie` パッケージを
`moon-component` の WASIp2 guest と組み合わせる実行可能サンプルです。

- Guest world: `wasi:cli/command@0.2.9`
- Spin trigger: HTTP (`executor = { type = "wagi" }`)
- Router: `@mizchi/mars/router` + `@mizchi/mars/router/trie`
- Request path source: `wasi:cli/environment.get-arguments` の 1 要素目（WAGI の `PATH_INFO` 相当）
- HTTP method: 現状は `GET` 固定

## Why this example

`mizchi/mars@0.3.2` 全体は `PlatformContext` 依存により現状 `--target wasm` で
そのままはビルド不可ですが、`router` / `router/trie` は pure なので
WASM component 側の app 層で直接利用できます。

## Decomposition points

1. **Pure routing core**
`@mizchi/mars/router` と `@mizchi/mars/router/trie` は IO 依存を持たない。

2. **Runtime boundary**
`impl/impl.mbt` が `wasi:cli/*` FFI と WAGI レスポンス整形を担当。

3. **App boundary**
`app/lib.mbt` は `method + path -> RouteResponse` の純関数 API を提供。

この分割により、次段階では `mizchi/mars.mbt` 側で wasm 対応が進んだ時に、
`app` の実装を `@mars` 依存へ差し替えるだけで移行できます。

## Run

```bash
cd examples/spin-mars-router
just wasmtime-run
```

`wasmtime` 直実行時は引数で path を渡して確認できます:

```bash
wasmtime run component.wasm /users/42
```

Spin で確認:

```bash
cd examples/spin-mars-router
just spin-up
# another terminal
curl -i http://127.0.0.1:3000/
curl -i http://127.0.0.1:3000/users/42
curl -i http://127.0.0.1:3000/files/a/b
```

## Test

```bash
cd examples/spin-mars-router
just test
```
