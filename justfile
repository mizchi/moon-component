# moon-component
# Usage: just <command> [args]

moon_component := "moon-component"
moon_component_bin := "_build/native/release/build/src/main/main.exe"

default:
    @just --list

# Build the MoonBit native CLI
build-native:
    moon build --target native --release -C src/main

# Build the MoonBit JS CLI
build-js:
    moon build --target js --release -C src/main

# Package native binary (os arch)
dist-package os arch:
    ./tools/dist/package.sh {{os}} {{arch}}

# Install instructions
install:
    @echo "Install moon-component:"
    @echo "  - Local MoonBit build: just install-native (full features)"
    @echo "  - Prebuilt binaries: see README.md"

# Install MoonBit-native CLI to ~/.local/bin (full features)
install-native: build-native
    mkdir -p ~/.local/bin
    cp {{moon_component_bin}} ~/.local/bin/moon-component
    @echo "Installed MoonBit CLI to ~/.local/bin/moon-component"

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

# Update generated interface files
info:
    moon info

# Check code (native target required for oci_wasm dependency)
check:
    moon check --target native

# Clean build artifacts
clean:
    moon clean

# Build hello example
example-hello:
    {{moon_component}} generate examples/hello/wit/world.wit -p hello -o examples/hello
    moon build --target wasm --release --directory examples/hello
    {{moon_component}} componentize examples/hello/_build/wasm/release/build/src/src.wasm \
        --wit-dir examples/hello/wit \
        -o examples/hello/hello.component.wasm
    wasm-tools component wit examples/hello/hello.component.wasm

# Build hello-wite example (moon-component + wite integration)
example-hello-wite:
    {{moon_component}} generate examples/hello-wite/wit/world.wit -p hello-wite -o examples/hello-wite
    moon build --target wasm --release --directory examples/hello-wite
    {{moon_component}} componentize examples/hello-wite/_build/wasm/release/build/src/src.wasm \
        --wit-dir examples/hello-wite/wit \
        -o examples/hello-wite/hello-wite.component.wasm
    wite optimize examples/hello-wite/hello-wite.component.wasm \
        examples/hello-wite/hello-wite.min.wasm --kind=component -Oz
    wite analyze component examples/hello-wite/hello-wite.component.wasm

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
test-integration: test-zig-host test-swift-host
    @echo "All integration tests passed!"

# Run all integration tests including Scala and jco (requires sbt, pnpm)
test-integration-all: test-zig-host test-swift-host test-scala-host test-jco-host
    @echo "All integration tests (including Scala and jco) passed!"

# Local release prep: bump version, format, commit, tag
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
    git add -A
    git commit -m "Release v${ver}"
    git tag -a "v${ver}" -m "v${ver}"

# CI release: build artifacts only
release-ci os arch:
    ./tools/dist/package.sh {{os}} {{arch}}
