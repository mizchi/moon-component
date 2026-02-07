# Spin + Moon Component + Mars Router Split Example

`mizchi/mars.mbt` をそのまま依存せず、`router` / `router/trie` を分離して
`moon-component` の WASIp2 guest と組み合わせる実行可能サンプルです。

- Guest world: `wasi:cli/command@0.2.9`
- Spin trigger: HTTP (`executor = { type = "wagi" }`)
- Router: vendored `mars` trie router (`examples/spin-mars-router/mars_router`)
- Request path source: `wasi:cli/environment.get-arguments` の 1 要素目（WAGI の `PATH_INFO` 相当）
- HTTP method: 現状は `GET` 固定

## Why this example

`mizchi/mars@0.3.2` は現状 `--target wasm` でビルド不可なため、
まずは router 層のみを分解して WASM component に接続できるかを検証します。

## Decomposition points (for step 2)

1. **Pure routing core**
`mars_router/` と `mars_router/trie/` は IO 依存を持たない。

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
