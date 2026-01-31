# mizchi/wit_bindgen_mbt

WIT (WebAssembly Interface Types) to MoonBit code generator.

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

// Trait with normalized function names

///|
pub(open) trait Exports {
  blob_new(Self, data : Array[Byte]) -> Blob // [constructor]blob
  blob_size(Self, this : Blob) -> UInt // [method]blob.size
  blob_read(Self, this : Blob, offset : UInt, len : UInt) -> Array[Byte]
  create_blob(Self, data : Array[Byte]) -> Blob
  get_blob_size(Self, b : Blob) -> UInt
}
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

## Usage

```bash
# Generate JSON from WIT
wasm-tools component wit world.wit --json > resolve.json

# Add world_id wrapper
jq '{resolve: ., world_id: 0}' resolve.json > input.json

# Generate MoonBit code
wit-bindgen-moonbit input.json --project-name my-project --out-dir ./
```

## Examples

- `examples/hello` - Basic string export
- `examples/reverse` - String manipulation
- `examples/calc-impl` - Calculator with records
- `examples/tests/types-test` - All primitive and container types (MoonBit)
- `examples/tests/rust-guest` - Reference implementation (Rust wit-bindgen)
- `examples/tests/zig-guest` - Zig implementation using C bindings
- `examples/tests/resource-test` - Resource type (experimental)

## Integration Tests

Host implementations for testing generated WebAssembly modules:

| Host | Language | Test Level | Notes |
|------|----------|------------|-------|
| `examples/tests/rust-host` | Rust | Component | Full canonical ABI testing via wasmtime |
| `examples/tests/swift-host` | Swift | Core Wasm | Runtime testing via WasmKit (macOS 14+) |
| `examples/tests/scala-host` | Scala | Core Wasm | Runtime testing via Chicory (JDK 11+) |
| `examples/tests/zig-host` | Zig | Core Wasm | Binary format validation (export verification) |
| `examples/tests/jco-host` | JavaScript | Component | Node.js testing via jco transpiler |

```bash
# Run all integration tests (Rust, Zig, Swift)
just test-integration

# Run all integration tests including Scala and jco (requires sbt, pnpm)
just test-integration-all

# Run individual host tests
just test-rust-host
just test-swift-host
just test-scala-host
just test-zig-host
just test-jco-host
```
