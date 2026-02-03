# Core Module Plug Example

This example builds two components using the component-model text format and
uses `moon-component plug` to connect a core module export to a core module import.

Files:
- `socket.wat` imports a core module named `dep`
- `plug.wat` exports a core module named `dep`

Build:

```bash
wasm-tools parse socket.wat -o socket.wasm
wasm-tools parse plug.wat -o plug.wasm
```

Compose:

```bash
moon-component plug socket.wasm --plug plug.wasm -o composed.wasm
# or
just example-core-module-compose
```
