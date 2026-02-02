# Rust Guest Implementation

This directory contains a Rust implementation of the types-test WIT interface, compiled to WebAssembly Component.

## Purpose

- Reference implementation for cross-validating moon-component output
- Verify host implementations work correctly with canonical wit-bindgen output
- Demonstrate equivalent functionality in Rust

## Prerequisites

- Rust with `wasm32-wasip1` target
- cargo-component (optional, for component model)

```bash
rustup target add wasm32-wasip1
cargo install cargo-component
```

## Building

```bash
# Build core wasm module
cargo build --release --target wasm32-wasip1

# Build as component (requires cargo-component)
cargo component build --release
```

## Output

- Core wasm: `target/wasm32-wasip1/release/rust_guest.wasm`
- Component: `target/wasm32-wasip1/release/rust_guest.component.wasm`

## Testing with Hosts

```bash
# Test with Rust host
cd ../host/rust
cargo run --release -- types --wasm ../rust-guest/target/wasm32-wasip1/release/rust_guest.wasm

# Test with Swift host (core wasm only)
cd ../host/swift
swift run SwiftHost ../rust-guest/target/wasm32-wasip1/release/rust_guest.wasm
```

## Comparison

| Implementation | Language | Toolchain |
|----------------|----------|-----------|
| types-test | MoonBit | moon-component |
| rust-guest | Rust | wit-bindgen (canonical) |

Both should produce equivalent wasm exports and pass the same host tests.
