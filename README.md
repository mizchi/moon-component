# mizchi/moon_component

WebAssembly Component Model tooling for MoonBit.

## Installation

```bash
# Prebuilt binary (macOS/Linux)
curl -fsSL https://raw.githubusercontent.com/mizchi/moon-component/main/install.sh | bash

# Build from source (MoonBit)
moon build --target native --release src/cmd/moon-component

# Add to PATH (optional)
export PATH="$PWD/_build/native/release/build/src/cmd/moon-component:$PATH"

# Or install to ~/.local/bin
just install-native
```

Note:
- prebuilt macOS binaries are arm64 only. macOS x64 requires build from source.
- Requires [MoonBit](https://www.moonbitlang.com/) toolchain and [wasm-tools](https://github.com/bytecodealliance/wasm-tools) for componentize.

## Quick Start

```bash
# Generate bindings from WIT
moon-component generate wit/world.wit -o ./my-component -p my/project

# Build wasm module
moon build --target wasm --release --directory my-component

# Create component
moon-component componentize my-component/_build/wasm/release/build/impl/impl.wasm \
  --wit-dir my-component/wit -o my-component.wasm
```

## Commands

### `moon-component generate <wit-path>`

Generate MoonBit bindings from WIT files.

```bash
moon-component generate wit/world.wit -o ./component -p my/project
```

Options:
- `-o, --out-dir <dir>` - Output directory (default: stdout)
- `-p, --project-name <name>` - Project name for imports
- `--gen-dir <dir>` - Generated code directory (default: `gen`)
- `--impl-dir <dir>` - Implementation directory (default: `impl`)
- `--no-impl` - Don't generate impl files
- `--wkg` - Generate wkg.toml for wa.dev deployment
- `--wite` - Generate wite.config.jsonc for wite pipeline
- `--world <name>` - World to generate bindings for
- `--pkg-format <fmt>` - Package format: `json` (moon.pkg.json) or `dsl` (moon.pkg)
- `--js-string-builtins` - Enable JS String Builtins (wasm-gc only)

### `moon-component componentize <wasm-path>`

Create a WebAssembly component from a built core wasm module. Automatically detects and patches retptr imports.

```bash
moon build --target wasm --release
moon-component componentize _build/wasm/release/build/impl/impl.wasm \
  --wit-dir wit -o component.wasm
```

Options:
- `--wit <path>` - WIT directory (required)
- `--world <name>` - World name
- `-o <path>` - Output path (required)

### `moon-component fetch`

Fetch WIT packages from [wa.dev](https://wa.dev) registry via HTTP.

```bash
# Fetch specific packages
moon-component fetch wasi:http@0.2.0
moon-component fetch wasi:cli@0.2.0 wasi:io@0.2.0

# Auto-detect and fetch all dependencies from WIT
moon-component fetch --from-wit wit/world.wit --wit-dir wit
```

Options:
- `--registry <host>` - Registry host (default: wa.dev)
- `--wit-dir <dir>` - WIT output directory (default: wit)
- `--from-wit <path>` - Resolve WIT and fetch all dependencies

### `moon-component plug`

Plug components together (socket + plugs).

```bash
moon-component plug socket.wasm --plug plug.wasm -o composed.wasm
```

### `moon-component compose`

Compose components using WAC (WebAssembly Composition) syntax.

```bash
moon-component compose composition.wac -o composed.wasm
```

### `moon-component targets`

Validate component targets against WIT definitions.

```bash
moon-component targets component.wasm wit/ --world my-world
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
For Rust to MoonBit porting workflow, see `docs/rust-port.md`.

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

```moonbit nocheck
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

```moonbit nocheck
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

## Project Structure

```
moon-component/
├── src/                          # Codegen library (pure, no I/O)
│   ├── resolve/                  # WIT resolve types
│   ├── component/                # Component model operations
│   ├── wkg/                      # WKG registry URL helpers
│   ├── fetch/                    # HTTP-based WIT package fetching
│   ├── cabi/                     # Canonical ABI utilities
│   └── cmd/moon-component/       # CLI entry point
├── examples/
│   ├── hello/                    # Basic string export
│   ├── wasi-cli/                 # WASIp2 wasi:cli/run
│   └── tests/                    # Type test suites
└── tools/                        # CI/dist scripts
```

## Development

```bash
# Install dependencies
moon update

# Check (native target)
just check

# Run library tests
moon test -p mizchi/moon_component/src --target wasm-gc

# Build CLI
just build-native

# Install to ~/.local/bin
just install-native

# Format
just fmt
```

## Examples

- `examples/hello` - Basic string export
- `examples/wasi-cli` - WASIp2 wasi:cli/run with retptr patching
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

# Run individual host tests
just test-swift-host
just test-scala-host
just test-zig-host
just test-jco-host

# Rust host tests (optional)
just -f justfile.rust test-rust-host
```

## License

Apache-2.0
