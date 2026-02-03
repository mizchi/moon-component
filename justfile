# moon-component
# Usage: just <command> [args]

moon_component := "tools/moon-component/target/release/moon-component"

default:
    @just --list

# Build the moon-component CLI
build-cli:
    cargo build --release --manifest-path tools/moon-component/Cargo.toml

# Build the MoonBit native CLI
build-native:
    moon build --target native --release -C src/main

# Build the MoonBit JS CLI
build-js:
    moon build --target js --release -C src/main

# Package native binary (os arch)
dist-package os arch:
    ./tools/dist/package.sh {{os}} {{arch}}

# Build npm package assets
npm-build:
    ./tools/npm/build.sh

# Install moon-component to ~/.local/bin
install: build-cli
    mkdir -p ~/.local/bin
    cp {{moon_component}} ~/.local/bin/moon-component
    @echo "Installed moon-component to ~/.local/bin/moon-component"

# Run tests
test *args:
    moon test {{args}}

# Update wit-parser standard tests (from wasm-tools)
wit-tests-update:
    ./tools/wit-tests/update.sh

# Run wit-parser standard tests
wit-tests-run *args:
    ./tools/wit-tests/run.py {{args}}

# Update component-model reference tests
component-model-tests-update:
    ./tools/component-model-tests/update.sh

# Run component-model reference tests (requires wasmtime)
component-model-tests-run *args:
    ./tools/component-model-tests/run.py {{args}}

# Format code
fmt:
    moon fmt
    cargo fmt --manifest-path tools/moon-component/Cargo.toml

# Update generated interface files
info:
    moon info

# Check code
check:
    moon check
    cargo check --manifest-path tools/moon-component/Cargo.toml

# Clean build artifacts
clean:
    moon clean
    cargo clean --manifest-path tools/moon-component/Cargo.toml

# Build hello example
example-hello:
    {{moon_component}} generate examples/hello/wit/world.wit -p hello -o examples/hello
    moon build --target wasm --release --directory examples/hello
    {{moon_component}} componentize examples/hello/_build/wasm/release/build/src/src.wasm \
        --wit-dir examples/hello/wit \
        -o examples/hello/hello.component.wasm
    wasm-tools component wit examples/hello/hello.component.wasm

# Generate WIT from MoonBit (reverse example)
example-reverse:
    {{moon_component}} wit-from-moonbit examples/reverse -o examples/reverse/wit/world.wit -n myapp
    {{moon_component}} resolve-json examples/reverse/wit/world.wit | head -50

# Check WIT compatibility (reverse example)
example-reverse-check:
    {{moon_component}} wit-from-moonbit examples/reverse --check

# Build types-test example
example-types-test:
    moon build --target wasm --release --directory examples/tests/types-test

# Build core-module plug example
example-core-module-build:
    wasm-tools parse examples/core-module/socket.wat -o examples/core-module/socket.wasm
    wasm-tools parse examples/core-module/plug.wat -o examples/core-module/plug.wasm

# Compose core-module plug example
example-core-module-compose: example-core-module-build
    moon run src/main -- plug examples/core-module/socket.wasm --plug examples/core-module/plug.wasm -o examples/core-module/composed.wasm
    wasm-tools validate examples/core-module/composed.wasm

# Build rust-guest (reference implementation)
build-rust-guest:
    #!/usr/bin/env bash
    export RUSTUP_HOME="$HOME/.rustup"
    export CARGO_HOME="$HOME/.cargo"
    export PATH="$CARGO_HOME/bin:$RUSTUP_HOME/toolchains/stable-aarch64-apple-darwin/bin:$PATH"
    cargo build --release --target wasm32-unknown-unknown --manifest-path examples/tests/rust-guest/Cargo.toml
    wasm-tools component new examples/tests/rust-guest/target/wasm32-unknown-unknown/release/rust_guest.wasm -o examples/tests/rust-guest/rust-guest.component.wasm

# Test rust-guest with rust-host
test-rust-guest: build-rust-guest
    cargo run --release --manifest-path examples/host/rust/Cargo.toml -- types examples/tests/rust-guest/rust-guest.component.wasm

# Build zig-guest (Zig implementation using C bindings)
build-zig-guest:
    zig build -p examples/tests/zig-guest/zig-out --build-file examples/tests/zig-guest/build.zig
    wasm-tools component new examples/tests/zig-guest/zig-out/bin/zig-guest.wasm \
        --adapt examples/tests/zig-guest/adapters/wasi_snapshot_preview1.reactor.wasm \
        -o examples/tests/zig-guest/zig-guest.component.wasm

# Test zig-guest with rust-host
test-zig-guest: build-zig-guest
    cargo run --release --manifest-path examples/host/rust/Cargo.toml -- types examples/tests/zig-guest/zig-guest.component.wasm

# Run Rust host tests
test-rust-host test_type="types":
    cd examples/host/rust && cargo run --release -- {{test_type}}

# Build Zig host
build-zig-host:
    cd examples/host/zig && zig build

# Run Zig host tests (requires types-test wasm to be built)
test-zig-host: example-types-test build-zig-host
    cd examples/host/zig && zig build run

# Build Swift host (requires Swift 5.9+ and macOS 14+)
build-swift-host:
    swift build --package-path examples/host/swift

# Run Swift host tests (requires types-test wasm to be built)
test-swift-host: example-types-test build-swift-host
    examples/host/swift/.build/debug/SwiftHost examples/tests/types-test/_build/wasm/release/build/src/src.wasm

# Build Scala host (requires JDK 11+ and sbt)
build-scala-host:
    cd examples/host/scala && sbt compile

# Run Scala host tests (requires types-test wasm to be built)
test-scala-host: example-types-test
    cd examples/host/scala && sbt "run ../../tests/types-test/_build/wasm/release/build/src/src.wasm"

# Build jco host (transpile component to JS)
build-jco-host:
    pnpm --dir examples/host/jco install
    pnpm --dir examples/host/jco run transpile

# Run jco host tests (requires types-test component)
test-jco-host: build-jco-host
    pnpm --dir examples/host/jco run test

# Run all integration tests
test-integration: test-rust-host test-zig-host test-swift-host
    @echo "All integration tests passed!"

# Run all integration tests including Scala and jco (requires sbt, pnpm)
test-integration-all: test-rust-host test-zig-host test-swift-host test-scala-host test-jco-host
    @echo "All integration tests (including Scala and jco) passed!"

# Local release prep: bump version, format, build npm assets, commit, tag
release-local version:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Working tree is not clean. Commit or stash before release." >&2
        exit 1
    fi

    ver="{{version}}"
    ver="${ver#v}"

    python3 - "$ver" -c 'import json,sys; path="moon.mod.json"; version=sys.argv[1]; data=json.load(open(path,"r",encoding="utf-8")); data["version"]=version; f=open(path,"w",encoding="utf-8"); json.dump(data,f,indent=2,ensure_ascii=True); f.write("\\n"); f.close()'

    moon info
    moon fmt
    ./tools/npm/build.sh

    git add -A
    git commit -m "Release v${ver}"
    git tag -a "v${ver}" -m "v${ver}"

# CI release: build artifacts only
release-ci os arch:
    ./tools/dist/package.sh {{os}} {{arch}}
