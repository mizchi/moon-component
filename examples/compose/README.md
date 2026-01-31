# Multi-Component Composition Example

This example demonstrates how to compose multiple WebAssembly components using `moon-component bundle`.

## Structure

```
examples/compose/
├── moon-component.toml    # Bundle configuration
├── libs/
│   ├── math/component/    # Math library (exports example:math/operations)
│   └── strings/component/ # Strings library (exports example:strings/utils)
├── apps/
│   └── main/component/    # Main app (imports both, exports example:app/api)
└── dist/
    └── composed.wasm      # Final composed component
```

## Components

### math (example:math)
Exports `operations` interface:
- `add(a: s32, b: s32) -> s32`
- `multiply(a: s32, b: s32) -> s32`
- `factorial(n: u32) -> u64`

### strings (example:strings)
Exports `utils` interface:
- `reverse(s: string) -> string`
- `uppercase(s: string) -> string`
- `repeat(s: string, n: u32) -> string`

### app (example:app)
Imports both libraries and exports combined `api` interface:
- `calc-add`, `calc-multiply`, `calc-factorial` - delegating to math
- `str-reverse`, `str-uppercase`, `str-repeat` - delegating to strings
- `describe-factorial(n: u32) -> string` - combines both

## Building

```bash
# Build and compose all components
moon-component bundle -c moon-component.toml

# The composed component will be at dist/composed.wasm
```

## Configuration (moon-component.toml)

```toml
[bundle]
name = "example/composed-app"
output = "dist/composed.wasm"
entry = "apps/main/component"

[dependencies]
"example:math" = { path = "libs/math/component" }
"example:strings" = { path = "libs/strings/component" }

[build]
target = "wasm"
release = true
```

## How It Works

1. `moon-component bundle` builds each component:
   - libs/math/component -> _build/bundle/deps/example/math.wasm
   - libs/strings/component -> _build/bundle/deps/example/strings.wasm
   - apps/main/component -> _build/bundle/entry.wasm

2. Uses `wac plug` to compose them:
   - entry.wasm is the "socket" (has imports)
   - math.wasm and strings.wasm are "plugs" (provide exports)

3. Output is a single composed component with all imports satisfied
