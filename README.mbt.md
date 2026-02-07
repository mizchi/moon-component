# mizchi/moon_component

WebAssembly Component Model tooling for MoonBit.

## Installation

```bash
# Prebuilt binary (macOS/Linux)
curl -fsSL https://raw.githubusercontent.com/mizchi/moon-component/main/install.sh | bash

# Build from source (MoonBit)
moon build --target native --release -C src/main

# Add to PATH (optional)
export PATH="$PWD/_build/native/release/build/src/main:$PATH"
```

Note:
- prebuilt macOS binaries are arm64 only. macOS x64 requires build from source.

## Quick Start

```bash
# Create a new component project
moon-component new my-component

# Or initialize in existing MoonBit project
moon-component init

# Build component (generate + build + componentize)
moon-component component wit/world.wit -o my-component.wasm --release
```

## Commands

### `moon-component new <name>`

Create a new MoonBit component project with example WIT file.

```bash
moon-component new hello-world
cd hello-world
moon-component component wit/world.wit -o hello.wasm --release
```

### `moon-component generate <wit-path>`

Generate MoonBit bindings from WIT files.

```bash
moon-component generate wit/world.wit -o ./component -p my/project
```

Options:
- `-o, --out-dir <dir>` - Output directory (default: `.`)
- `-p, --project-name <name>` - Project name for imports
- `--gen-dir <dir>` - Generated code directory (default: `gen`)
- `--impl-dir <dir>` - Implementation directory (default: `impl`)
- `--no-impl` - Don't generate impl files
- `--wkg` - Generate wkg.toml for wa.dev deployment
- `-w, --world <world>` - World to generate bindings for

### `moon-component component <wit-path>`

Full workflow: generate + build + componentize.

```bash
moon-component component wit/world.wit -o output.wasm --release
```

### `moon-component componentize <wasm-path>`

Create a WebAssembly component from a built wasm module.

```bash
moon build --target wasm --release
moon-component componentize target/wasm/release/build/main/main.wasm \
  --wit-dir wit -o component.wasm
```

### `moon-component compose`

Compose components using a config file (default) or a compose file (.wac).

```bash
# Default entry: config file
moon-component compose -c moon-component.toml

# Or use a compose file directly
moon-component compose composition.wac -o composed.wasm
```

Example compose file (`composition.wac`):
```wac
package example:composed;

let app = new app:component { ... };
let lib = new lib:component { ... };

// Wire lib exports to app imports
let composed = new app { api: lib.api };

export composed...;
```

### Config-based composition

Bundle components from a workspace config file. Automatically builds all components and composes them.

```bash
# Use moon-component.toml
moon-component compose -c moon-component.toml

# Custom config file
moon-component compose -c my-config.toml

# Only build components, don't compose
moon-component compose -c moon-component.toml --build-only

# Preview generated compose file without executing
moon-component compose -c moon-component.toml --dry-run
```

## Bundle Configuration

Create `moon-component.toml` for declarative composition:

```toml
[bundle]
name = "my/app"
output = "dist/app.wasm"
entry = "apps/main/component"

# External imports (left unresolved for runtime)
externals = ["wasi:io/*", "wasi:cli/*"]

# Optional: use explicit compose file instead of auto-generation

[dependencies]
"mizchi:flatbuffers" = { path = "libs/flatbuffers/component" }
"mizchi:json" = { path = "libs/json/component" }

# Prebuilt component (no build)
# "local:regex/regex" = { component = "path/to/regex_guest.wasm" }

[build]
target = "wasm"
release = true
```

### How It Works

1. Reads `moon-component.toml`
2. Builds entry and all dependency components (parallel-ready)
3. Auto-generates compose file (or uses explicit one)
4. Composes the final component

### Generated Compose File Example

```wac
package my:app:composed;

let mizchi_flatbuffers = new mizchi:flatbuffers {};
let mizchi_json = new mizchi:json {};

let entry = new entry:component {
  "mizchi:flatbuffers": mizchi_flatbuffers."mizchi:flatbuffers",
  "mizchi:json": mizchi_json."mizchi:json",
};

export entry...;
```

## Monorepo Component Composition

In a monorepo with multiple MoonBit libraries:

```
monorepo/
├── moon-component.toml           # Bundle config
├── libs/
│   ├── flatbuffers/component/    # flatbuffers component
│   └── json/component/           # json component
└── apps/
    └── main/component/           # app that imports libs
```

```bash
# One command to build and compose everything
moon-component compose -c moon-component.toml
```

### Manual Composition (Alternative)

For fine-grained control, use a compose file directly:

```bash
moon-component compose composition.wac -o app.wasm
```

## Generated Directory Structure

```
component/
├── moon.mod.json
├── wit/
│   └── world.wit          # WIT definition
├── gen/                   # Generated code (regenerated)
│   └── cabi/
│       ├── moon.pkg.json
│       └── cabi.mbt       # Canonical ABI helpers
└── impl/                  # Implementation (preserved)
    ├── moon.pkg.json      # is-main: true
    ├── bindings.mbt       # Generated FFI glue (regenerated)
    └── impl.mbt           # User implementation (stub, preserved)
```

- `gen/` - Regenerated on each `generate` call
- `impl/bindings.mbt` - Regenerated (FFI glue)
- `impl/impl.mbt` - Preserved (user implementation stub)
- `impl/moon.pkg.json` - Preserved (user can add imports)

## Supported WIT Types

| WIT Type | MoonBit Type | Notes |
|----------|--------------|-------|
| `bool` | `Bool` | |
| `u8` | `Byte` | |
| `u16`, `u32` | `UInt` | |
| `u64` | `UInt64` | |
| `s8`, `s16`, `s32` | `Int` | |
| `s64` | `Int64` | |
| `f32` | `Float` | |
| `f64` | `Double` | |
| `char` | `Char` | |
| `string` | `String` | UTF-8 encoded |
| `list<T>` | `Array[T]` | |
| `option<T>` | `T?` | |
| `result<T, E>` | `Result[T, E]` | |
| `tuple<...>` | `(T1, T2, ...)` | |
| `record` | `struct` | |
| `variant` | `enum` | |
| `enum` | `enum` | With `from_ordinal`/`ordinal` |
| `flags` | `struct` (bitmask) | With `from_bits`/`to_bits` |
| `resource` | `struct(Int)` | Handle-based (experimental) |

## Resource Support (Experimental)

Resource types are supported with the following constraints:

For wasm-gc specifics, see `docs/wasm-gc-component-resources.md`.
For Rust → MoonBit porting workflow, see `docs/rust-port.md`.

### Constraints

1. **Handle-based only**: Resources are represented as `i32` handles (indices into a handle table)
2. **No borrow/own distinction**: Both `borrow<T>` and `own<T>` are treated identically as handles
3. **No automatic lifetime management**: Manual cleanup required (no finalizers in wasm-gc yet)
4. **MoonBit-side handle table**: Resource data is managed in MoonBit, not by the host

### Example WIT

```wit
interface blob-store {
  resource blob {
    constructor(data: list<u8>);
    size: func() -> u32;
    read: func(offset: u32, len: u32) -> list<u8>;
  }

  create-blob: func(data: list<u8>) -> own<blob>;
  get-blob-size: func(b: borrow<blob>) -> u32;
}
```

### Generated MoonBit Code

```moonbit
// Resource type (handle)

///|
pub(all) struct Blob(Int) derive(Show, Eq)

// Exported functions with normalized names

///|
pub fn blob_new(data : Array[Byte]) -> Blob // [constructor]blob
pub fn blob_size(this : Blob) -> UInt // [method]blob.size
pub fn blob_read(this : Blob, offset : UInt, len : UInt) -> Array[Byte]
pub fn create_blob(data : Array[Byte]) -> Blob
pub fn get_blob_size(b : Blob) -> UInt
```

### Implementation Pattern (Copy-based)

```moonbit
// Handle table for resource storage

///|
let blob_table : Ref[Array[Array[Byte]]] = { val: [] }

///|
fn allocate_blob(data : Array[Byte]) -> @exports.Blob {
  let handle = blob_table.val.length()
  blob_table.val.push(data)
  @exports.Blob(handle)
}

///|
fn get_blob(handle : @exports.Blob) -> Array[Byte] {
  blob_table.val[handle.0]
}
```

### Why Handle-based?

The [WebAssembly Component Model](https://github.com/WebAssembly/component-model/blob/main/design/mvp/CanonicalABI.md) specifies resources as opaque handles managed by a per-instance handle table. This approach:

- Matches the Canonical ABI specification
- Works with both wasm and wasm-gc targets
- Allows future migration to native wasm-gc resource support when standardized

See [Pre-Proposal: Wasm GC Support in Canonical ABI](https://github.com/WebAssembly/component-model/issues/525) for ongoing standardization work.

## Examples

- `examples/hello` - Basic string export
- `examples/reverse` - String manipulation
- `examples/calc-impl` - Calculator with records
- `examples/regex` - Rust guest + MoonBit host (regex)
- `examples/spin-wagi` - Spin HTTP trigger (WAGI executor) + WASIp2 `wasi:cli/run`
- `examples/tests/types-test` - All primitive and container types (MoonBit)
- `examples/tests/rust-guest` - Reference implementation (Rust wit-bindgen)
- `examples/tests/zig-guest` - Zig implementation using C bindings
- `examples/tests/resource-test` - Resource type (experimental)

## Integration Tests

Host implementations for testing generated WebAssembly modules:

| Host | Language | Test Level | Notes |
|------|----------|------------|-------|
| `examples/host/rust` | Rust | Component | Full canonical ABI testing via wasmtime |
| `examples/host/swift` | Swift | Core Wasm | Runtime testing via WasmKit (macOS 14+) |
| `examples/host/scala` | Scala | Core Wasm | Runtime testing via Chicory (JDK 11+) |
| `examples/host/zig` | Zig | Core Wasm | Binary format validation (export verification) |
| `examples/host/jco` | JavaScript | Component | Node.js testing via jco transpiler |

```bash
# Run all integration tests (Zig, Swift)
just test-integration

# Run all integration tests including Scala and jco (requires sbt, pnpm)
just test-integration-all

# Run individual host tests (non-Rust)
just test-swift-host
just test-scala-host
just test-zig-host
just test-jco-host

# Rust host tests (optional)
just -f justfile.rust test-rust-host
```
