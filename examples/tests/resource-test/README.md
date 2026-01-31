# Resource Test (Experimental)

This example demonstrates WIT resource type support with handle-based implementation.

## Constraints

- Resources are `i32` handles (not GC objects)
- `borrow<T>` and `own<T>` are treated identically
- Handle table managed in MoonBit, not host
- No automatic cleanup (manual drop required)

## WIT Definition

```wit
resource blob {
  constructor(data: list<u8>);
  size: func() -> u32;
  read: func(offset: u32, len: u32) -> list<u8>;
  write: func(offset: u32, data: list<u8>);
}

create-blob: func(data: list<u8>) -> own<blob>;
get-blob-size: func(b: borrow<blob>) -> u32;
consume-blob: func(b: own<blob>) -> list<u8>;
```

## Function Name Mapping

| WIT | MoonBit |
|-----|---------|
| `[constructor]blob` | `blob_new` |
| `[method]blob.size` | `blob_size` |
| `[method]blob.read` | `blob_read` |
| `[method]blob.write` | `blob_write` |

## Build

```bash
moon build --target wasm
```
