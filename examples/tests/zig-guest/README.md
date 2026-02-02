# Zig Guest Implementation

Zig implementation of the types-test WIT interface using wit-bindgen C bindings.

## Prerequisites

- Zig 0.15+
- wit-bindgen CLI (`cargo install wit-bindgen-cli`)
- wasm-tools (`cargo install wasm-tools`)

## How it Works

1. **Generate C bindings** from WIT using `wit-bindgen c`
2. **Implement exports in Zig** using `@cImport` to access C bindings
3. **Compile to wasm32-wasi** with libc linked
4. **Create component** using `wasm-tools component new` with WASI adapter

## Build

```bash
# Generate C bindings (already done)
wit-bindgen c --autodrop-borrows yes ./wit --out-dir src/bindings

# Build wasm
zig build

# Create component with WASI adapter
wasm-tools component new zig-out/bin/zig-guest.wasm \
  --adapt adapters/wasi_snapshot_preview1.reactor.wasm \
  -o zig-guest.component.wasm
```

## Test

```bash
# Test with rust host (requires WASI support)
cargo run --release --manifest-path ../host/rust/Cargo.toml -- types zig-guest.component.wasm
```

## Key Implementation Notes

### Memory Allocation

Use `std.c.malloc` for allocations that will be freed by `post_return`:

```zig
const ptr: [*]u8 = @ptrCast(std.c.malloc(len) orelse return);
```

### C Binding Access

```zig
const c = @cImport({
    @cInclude("types_test.h");
});

// Use generated types
const String = c.types_test_string_t;

// Use helper functions
c.types_test_string_dup(ret, "hello");
```

### Result Type Convention

The C binding wrapper negates the return value:
- Return `true` for success (wrapper sets `is_err = false`)
- Return `false` for error (wrapper sets `is_err = true`)

```zig
export fn exports_local_types_test_containers_divide(a: i32, b: i32, ret: *i32, err: *String) bool {
    if (b == 0) {
        c.types_test_string_dup(err, "division by zero");
        return false; // Error case
    }
    ret.* = @divTrunc(a, b);
    return true; // Success case
}
```

## File Structure

```
zig-guest/
├── build.zig              # Zig build script
├── src/
│   ├── main.zig           # Implementation
│   └── bindings/          # Generated C bindings
│       ├── types_test.h
│       ├── types_test.c
│       └── types_test_component_type.o
├── wit/
│   └── world.wit          # WIT interface definition
├── adapters/
│   └── wasi_snapshot_preview1.reactor.wasm
└── zig-guest.component.wasm  # Final component
```

## Comparison with Other Approaches

| Approach | Pros | Cons |
|----------|------|------|
| C bindings (this) | Stable, well-tested | Requires libc, WASI |
| zig-wasm/wit-bindgen | Native Zig | Still in development |
| Pure manual exports | No dependencies | Very complex |
