# Reverse Example: MoonBit to WIT

This example demonstrates generating WIT from MoonBit exports.

## Define Exports in MoonBit

Note: This `wit-from-moonbit` flow still requires `pub(open) trait Exports`.
`moon-component generate` output uses direct functions instead.

```moonbit
// src/exports.mbt

pub(all) struct Point {
  x : Int
  y : Int
}

// Enum must be const-only (no payload)
pub(all) enum Color {
  Red
  Green
  Blue
}

pub(open) trait Exports {
  greet(Self, name : String) -> String
  add(Self, a : Int, b : Int) -> Int
  create_point(Self, x : Int, y : Int) -> Point
  get_color(Self, name : String) -> Color
}
```

## Check WIT Compatibility

```bash
wit-bindgen-mbt wit-from-moonbit . --check
```

Output:
```
✅ WIT compatibility check passed!
   2 type(s), 4 method(s) found
```

## Generate WIT

```bash
wit-bindgen-mbt wit-from-moonbit . -o wit/world.wit -n myapp
```

## Generated WIT

```wit
package myapp:component;

interface exports {
  enum color {
    red,
    green,
    blue,
  }

  record point {
    x: s32,
    y: s32,
  }

  greet: func(p1: string) -> string;
  add: func(p1: s32, p2: s32) -> s32;
  create-point: func(p1: s32, p2: s32) -> point;
  get-color: func(p1: string) -> color;
}

world component {
  export exports;
}
```

## Type Mapping

| MoonBit | WIT |
|---------|-----|
| `Int` | `s32` |
| `Int64` | `s64` |
| `UInt` | `u32` |
| `UInt64` | `u64` |
| `Float` | `f32` |
| `Double` | `f64` |
| `Bool` | `bool` |
| `Char` | `char` |
| `String` | `string` |
| `Array[T]` | `list<T>` |
| `T?` / `Option[T]` | `option<T>` |
| `Result[T, E]` | `result<T, E>` |
| `pub(all) struct` | `record` |
| `pub(all) enum` (const-only) | `enum` |

## Validation Rules

| Rule | Error/Warning |
|------|---------------|
| `pub(open) trait Exports` required | Error |
| Enum with payload (e.g., `Foo(Int)`) | Error |
| Function types `(T) -> U` | Error |
| `Map[K, V]` | Error |
| Reference types `&T`, `Ref[T]` | Error |
| Non-`pub(all)` struct/enum | Warning |

## Sources

- [MoonBit Enum Documentation](https://tour.moonbitlang.com/data-types/enum/index.html)
- [MoonBit Textbook - Tuples, Structs & Enums](https://moonbitlang.github.io/moonbit-textbook/tuples-structs-enums/)
