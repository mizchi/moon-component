# Hello Component Example

Simple WebAssembly Component that exports a `greet` function.

## WIT Definition

```wit
package local:hello;

interface greet {
  greet: func(name: string) -> string;
}

world hello {
  export greet;
}
```

## Build

```bash
# Generate bindings
wit-bindgen-mbt generate wit/world.wit -p hello

# Build
moon build --target wasm --release

# Create component
wit-bindgen-mbt componentize _build/wasm/release/build/src/src.wasm --wit-dir wit -o hello.component.wasm
```

## Verify

```bash
wasm-tools component wit hello.component.wasm
```

Output:
```
package root:component;

world root {
  export local:hello/greet;
}
```
