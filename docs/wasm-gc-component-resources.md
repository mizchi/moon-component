# Wasm GC Component Model: Resource Management

This document summarizes how resource types are handled when you build a
WebAssembly Component with the wasm-gc target in this repository
("moon-component").

## TL;DR

- Resource types are still handle-based (i32 indices) even on wasm-gc.
- There is no GC-aware canonical ABI for resources in this tool yet.
- `own<T>` and `borrow<T>` are treated the same (no lifetime checks).
- You are responsible for resource lifetime management (manual drop/close).

## What Actually Happens Today

### 1) WIT resource -> MoonBit handle

When the generator sees a WIT `resource`, it produces a MoonBit newtype
that wraps an `Int` handle. The ABI boundary always carries that handle as
an `i32`.

### 2) Canonical ABI is still used

Even for wasm-gc, componentization uses the canonical ABI (lift/lower) with
linear memory conventions. The generated `cabi` helpers perform explicit
serialization/deserialization for strings, lists, records, variants, etc.

This means wasm-gc does not magically turn resource values into GC
references across the component boundary. The boundary is still "bytes +
handles".

### 3) Resource data is stored on the guest side

The recommended pattern in this repo is to keep a MoonBit-side table
(e.g. `Array`/`Map`) that holds the actual resource payload. The exported
API returns/accepts handles that index into that table.

### 4) No automatic drop/rep

The generator does not emit or manage resource drop/rep hooks. There is
also no automatic host-driven cleanup. If you need cleanup, you must expose
explicit functions (e.g. `close`, `free`, `release`) and remove the entry
from your table yourself.

## Implications

- GC only manages MoonBit heap objects inside the guest. It does not manage
  host resources or cross-component ownership.
- If you keep handles forever, you will leak resource entries unless you
  provide an explicit cleanup API.
- `borrow` vs `own` is not enforced; treat them as the same handle type.

## What This Is NOT (Yet)

- A GC-aware canonical ABI for resources.
- Direct passing of GC references across the component boundary.
- Automatic resource lifetime tracking.

If a GC-aware canonical ABI becomes standardized, moon-component will need
explicit updates to take advantage of it. For now, the handle-table model is
the supported and tested behavior.
