///|
fn normalize_core_name(name : Bytes) -> String {
  let chars : Array[Char] = []
  for c in bytes_to_string(name) {
    let norm = if c == '_' {
      '-'
    } else if c.is_ascii_uppercase() {
      c.to_ascii_lowercase()
    } else {
      c
    }
    chars.push(norm)
  }
  String::from_array(chars)
}

///|
priv struct CoreModuleExtern {
  name : Bytes
  kind : UInt
  type_idx : UInt
}

///|
priv struct CoreModuleTypeDetail {
  types : Array[Bytes]
  imports : Array[CoreModuleExtern]
  exports : Array[CoreModuleExtern]
}

///|
fn parse_core_module_type_detail(
  raw : Bytes,
) -> Result[CoreModuleTypeDetail, String] {
  let parser = Parser::new(raw)
  try {
    let kind = parser.read_byte().to_uint()
    if kind != 0x50 {
      return Err("not a module type")
    }
    let decl_count = parser.read_u32_leb128()
    let types : Array[Bytes] = []
    let imports : Array[CoreModuleExtern] = []
    let exports : Array[CoreModuleExtern] = []
    for _ in 0U..<decl_count {
      let decl = parser.read_byte().to_uint()
      match decl {
        0x00 => {
          let name = parser.read_name()
          let ext_kind = parser.read_byte().to_uint()
          let type_idx = parser.read_u32_leb128()
          imports.push({ name, kind: ext_kind, type_idx })
        }
        0x01 => {
          let entries = parse_core_rec_group(parser)
          for entry in entries {
            types.push(entry)
          }
        }
        0x02 => {
          let start = parser.get_pos()
          let _ = parser.read_byte()
          let _ = parser.read_u32_leb128()
          let _ = parser.read_u32_leb128()
          let end = parser.get_pos()
          types.push(parser.slice(start, end))
        }
        0x03 => {
          let name = parser.read_name()
          let ext_kind = parser.read_byte().to_uint()
          let type_idx = parser.read_u32_leb128()
          exports.push({ name, kind: ext_kind, type_idx })
        }
        _ => return Err("invalid module type decl")
      }
    }
    Ok({ types, imports, exports })
  } catch {
    e => Err("core module type parse error: " + e.to_string())
  }
}

///|
fn skip_wasm_limits(parser : Parser) -> Unit raise ParseError {
  let flags = parser.read_byte().to_uint()
  let _ = parser.read_u32_leb128()
  if flags == 0x01 {
    let _ = parser.read_u32_leb128()
  } else if flags != 0x00 {
    raise ParseError::InvalidFormat("invalid limits")
  }
}

///|
fn skip_wasm_table_type(parser : Parser) -> Unit raise ParseError {
  let _ = parser.read_byte()
  skip_wasm_limits(parser)
}

///|
fn skip_wasm_memory_type(parser : Parser) -> Unit raise ParseError {
  skip_wasm_limits(parser)
}

///|
fn skip_wasm_global_type(parser : Parser) -> Unit raise ParseError {
  let _ = parser.read_byte()
  let _ = parser.read_byte()
}

///|
fn parse_wasm_func_type_raw(parser : Parser) -> Bytes raise ParseError {
  let start = parser.get_pos()
  let form = parser.read_byte()
  if form.to_uint() != 0x60 {
    raise ParseError::InvalidFormat("invalid func type")
  }
  let param_count = parser.read_u32_leb128()
  for _ in 0U..<param_count {
    let _ = parser.read_byte()
  }
  let result_count = parser.read_u32_leb128()
  for _ in 0U..<result_count {
    let _ = parser.read_byte()
  }
  let end = parser.get_pos()
  parser.slice(start, end)
}

///|
fn parse_core_module_detail_from_wasm(
  bytes : Bytes,
  opts : TypeCheckOptions,
) -> Result[CoreModuleTypeDetail, String] {
  let parser = Parser::new(bytes)
  try {
    let magic = parser.read_bytes(4)
    if magic.length() < 4 ||
      magic[0] != 0x00U.to_byte() ||
      magic[1] != 0x61U.to_byte() ||
      magic[2] != 0x73U.to_byte() ||
      magic[3] != 0x6dU.to_byte() {
      return Err("invalid core module magic")
    }
    let version = parser.read_bytes(4)
    if version.length() < 4 ||
      version[0] != 0x01U.to_byte() ||
      version[1] != 0x00U.to_byte() ||
      version[2] != 0x00U.to_byte() ||
      version[3] != 0x00U.to_byte() {
      return Err("unsupported core module version")
    }
    let types : Array[Bytes] = []
    let imports : Array[CoreModuleExtern] = []
    let exports : Array[CoreModuleExtern] = []
    let func_type_indices : Array[UInt] = []
    while not(parser.eof()) {
      let section_id = parser.read_byte().to_uint()
      let section_size = parser.read_u32_leb128()
      let section_start = parser.get_pos()
      let section_end = section_start + section_size.reinterpret_as_int()
      match section_id {
        1 => {
          let count = parser.read_u32_leb128()
          for _ in 0U..<count {
            let raw = parse_wasm_func_type_raw(parser)
            types.push(raw)
          }
        }
        2 => {
          let count = parser.read_u32_leb128()
          for _ in 0U..<count {
            let _module = parser.read_name()
            let name = parser.read_name()
            let kind = parser.read_byte().to_uint()
            match kind {
              0x00 => {
                let type_idx = parser.read_u32_leb128()
                imports.push({ name, kind, type_idx })
                func_type_indices.push(type_idx)
              }
              0x01 => {
                skip_wasm_table_type(parser)
                if not(opts.best_effort) {
                  return Err("unsupported core module import kind: table")
                }
              }
              0x02 => {
                skip_wasm_memory_type(parser)
                if not(opts.best_effort) {
                  return Err("unsupported core module import kind: memory")
                }
              }
              0x03 => {
                skip_wasm_global_type(parser)
                if not(opts.best_effort) {
                  return Err("unsupported core module import kind: global")
                }
              }
              _ =>
                return Err(
                  "invalid core module import kind: 0x\{kind.to_string()}",
                )
            }
          }
        }
        3 => {
          let count = parser.read_u32_leb128()
          for _ in 0U..<count {
            let type_idx = parser.read_u32_leb128()
            func_type_indices.push(type_idx)
          }
        }
        7 => {
          let count = parser.read_u32_leb128()
          for _ in 0U..<count {
            let name = parser.read_name()
            let kind = parser.read_byte().to_uint()
            let index = parser.read_u32_leb128()
            if kind == 0x00 {
              if index >= func_type_indices.length().reinterpret_as_uint() {
                return Err("core module export func index out of range")
              }
              let type_idx = func_type_indices[index.reinterpret_as_int()]
              exports.push({ name, kind, type_idx })
            } else if not(opts.best_effort) {
              return Err(
                "unsupported core module export kind: 0x\{kind.to_string()}",
              )
            }
          }
        }
        _ => parser.set_pos(section_end)
      }
      if parser.get_pos() < section_end {
        parser.set_pos(section_end)
      }
    }
    Ok({ types, imports, exports })
  } catch {
    e => Err("core module wasm parse error: " + e.to_string())
  }
}

///|
fn empty_core_module_detail() -> CoreModuleTypeDetail {
  { types: [], imports: [], exports: [] }
}

///|
fn check_core_module_detail_subtype(
  a : CoreModuleTypeDetail,
  b : CoreModuleTypeDetail,
  opts : TypeCheckOptions,
) -> Result[Unit, String] {
  let type_map : Map[UInt, UInt] = {}
  match check_core_module_imports_subtype(a, b, type_map, opts) {
    Ok(_) => check_core_module_exports_subtype(a, b, type_map, opts)
    Err(e) => Err(e)
  }
}

///|
fn resolve_core_module_type_detail(
  types : Array[CoreTypeRaw],
  type_ref : ComponentTypeRef,
  opts : TypeCheckOptions,
) -> Result[CoreModuleTypeDetail, String] {
  match type_ref {
    ComponentTypeRef::Module(idx) =>
      match get_core_type_raw(types, idx) {
        Some(raw) =>
          if raw.kind != CoreTypeKind::Module {
            if opts.best_effort {
              Ok(empty_core_module_detail())
            } else {
              Err("core module type mismatch")
            }
          } else {
            parse_core_module_type_detail(raw.raw)
          }
        None =>
          if opts.best_effort {
            Ok(empty_core_module_detail())
          } else {
            Err("core module type index out of range")
          }
      }
    _ => Err("expected core module type")
  }
}

///|
fn resolve_core_module_export_detail(
  detail : ComponentDetail,
  index : UInt,
  opts : TypeCheckOptions,
) -> Result[CoreModuleTypeDetail, String] {
  let import_types : Array[ComponentTypeRef] = []
  for imp in detail.imports {
    if imp.kind == ExternKind::CoreModule {
      import_types.push(imp.type_ref)
    }
  }
  if index < import_types.length().reinterpret_as_uint() {
    let type_ref = import_types[index.reinterpret_as_int()]
    resolve_core_module_type_detail(detail.core_types, type_ref, opts)
  } else {
    let def_idx = index - import_types.length().reinterpret_as_uint()
    if def_idx < detail.core_modules.length().reinterpret_as_uint() {
      parse_core_module_detail_from_wasm(
        detail.core_modules[def_idx.reinterpret_as_int()],
        opts,
      )
    } else if opts.best_effort {
      Ok(empty_core_module_detail())
    } else {
      Err("core module export index out of range")
    }
  }
}

///|
fn parse_core_rec_group(parser : Parser) -> Array[Bytes] raise ParseError {
  let kind = match parser.peek_byte() {
    Some(b) => b.to_uint()
    None => raise ParseError::UnexpectedEof
  }
  let entries : Array[Bytes] = []
  if kind == 0x4F {
    let _ = parser.read_byte()
    let count = parser.read_u32_leb128()
    for _ in 0U..<count {
      let start = parser.get_pos()
      skip_core_sub_type_for_module_type(parser)
      let end = parser.get_pos()
      entries.push(parser.slice(start, end))
    }
  } else {
    let start = parser.get_pos()
    skip_core_sub_type_for_module_type(parser)
    let end = parser.get_pos()
    entries.push(parser.slice(start, end))
  }
  entries
}

///|
fn skip_core_sub_type_for_module_type(parser : Parser) -> Unit raise ParseError {
  let _ = parser.read_byte()
  skip_core_func_type_for_module_type(parser)
}

///|
fn skip_core_func_type_for_module_type(
  parser : Parser,
) -> Unit raise ParseError {
  let param_count = parser.read_u32_leb128()
  for _ in 0U..<param_count {
    let _ = parser.read_byte()
  }
  let result_count = parser.read_u32_leb128()
  for _ in 0U..<result_count {
    let _ = parser.read_byte()
  }
}

///|
fn core_extern_map(
  items : Array[CoreModuleExtern],
) -> Result[Map[String, CoreModuleExtern], String] {
  let map : Map[String, CoreModuleExtern] = {}
  for item in items {
    let key = normalize_core_name(item.name)
    match map.get(key) {
      Some(existing) =>
        if existing.kind != item.kind || existing.type_idx != item.type_idx {
          return Err("core module extern kind mismatch")
        }
      None => map.set(key, item)
    }
  }
  Ok(map)
}

///|
fn check_core_module_imports_subtype(
  a : CoreModuleTypeDetail,
  b : CoreModuleTypeDetail,
  type_map : Map[UInt, UInt],
  opts : TypeCheckOptions,
) -> Result[Unit, String] {
  let map_a = match core_extern_map(a.imports) {
    Ok(v) => v
    Err(e) => return mismatch_or_ok(e, opts)
  }
  let map_b = match core_extern_map(b.imports) {
    Ok(v) => v
    Err(e) => return mismatch_or_ok(e, opts)
  }
  for name, item_a in map_a {
    match map_b.get(name) {
      Some(item_b) =>
        if item_b.kind != item_a.kind {
          return mismatch_or_ok("core module import kind mismatch", opts)
        } else {
          match
            check_core_type_index_pair(
              item_a.type_idx,
              item_b.type_idx,
              a.types,
              b.types,
              type_map,
              opts,
            ) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        }
      None => return mismatch_or_ok("core module import missing", opts)
    }
  }
  Ok(())
}

///|
fn check_core_module_exports_subtype(
  a : CoreModuleTypeDetail,
  b : CoreModuleTypeDetail,
  type_map : Map[UInt, UInt],
  opts : TypeCheckOptions,
) -> Result[Unit, String] {
  let map_a = match core_extern_map(a.exports) {
    Ok(v) => v
    Err(e) => return mismatch_or_ok(e, opts)
  }
  let map_b = match core_extern_map(b.exports) {
    Ok(v) => v
    Err(e) => return mismatch_or_ok(e, opts)
  }
  for name, item_b in map_b {
    match map_a.get(name) {
      Some(item_a) =>
        if item_a.kind != item_b.kind {
          return mismatch_or_ok("core module export kind mismatch", opts)
        } else {
          match
            check_core_type_index_pair(
              item_a.type_idx,
              item_b.type_idx,
              a.types,
              b.types,
              type_map,
              opts,
            ) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        }
      None => return mismatch_or_ok("core module export missing", opts)
    }
  }
  Ok(())
}

///|
fn check_core_type_index_pair(
  a_idx : UInt,
  b_idx : UInt,
  types_a : Array[Bytes],
  types_b : Array[Bytes],
  type_map : Map[UInt, UInt],
  opts : TypeCheckOptions,
) -> Result[Unit, String] {
  match type_map.get(a_idx) {
    Some(existing) =>
      if existing != b_idx {
        return mismatch_or_ok("core type index mapping mismatch", opts)
      }
    None => type_map.set(a_idx, b_idx)
  }
  if a_idx >= types_a.length().reinterpret_as_uint() ||
    b_idx >= types_b.length().reinterpret_as_uint() {
    return mismatch_or_ok("core type index out of range", opts)
  }
  let raw_a = types_a[a_idx.reinterpret_as_int()]
  let raw_b = types_b[b_idx.reinterpret_as_int()]
  if raw_a == raw_b {
    Ok(())
  } else {
    mismatch_or_ok("core type mismatch", opts)
  }
}

///|
fn get_core_type_raw(types : Array[CoreTypeRaw], idx : UInt) -> CoreTypeRaw? {
  if idx < types.length().reinterpret_as_uint() {
    Some(types[idx.reinterpret_as_int()])
  } else {
    None
  }
}

///|
fn check_core_module_type_subtype(
  types_a : Array[CoreTypeRaw],
  types_b : Array[CoreTypeRaw],
  a_idx : UInt,
  b_idx : UInt,
  opts : TypeCheckOptions,
) -> Result[Unit, String] {
  let a_raw = get_core_type_raw(types_a, a_idx)
  let b_raw = get_core_type_raw(types_b, b_idx)
  match (a_raw, b_raw) {
    (Some(ta), Some(tb)) =>
      if ta.kind != CoreTypeKind::Module || tb.kind != CoreTypeKind::Module {
        mismatch_or_ok("core module type mismatch", opts)
      } else {
        let detail_a = parse_core_module_type_detail(ta.raw)
        let detail_b = parse_core_module_type_detail(tb.raw)
        match (detail_a, detail_b) {
          (Ok(da), Ok(db)) => {
            let type_map : Map[UInt, UInt] = {}
            match check_core_module_imports_subtype(da, db, type_map, opts) {
              Ok(_) => check_core_module_exports_subtype(da, db, type_map, opts)
              Err(e) => Err(e)
            }
          }
          _ =>
            if ta.raw == tb.raw {
              Ok(())
            } else if opts.best_effort {
              Ok(())
            } else {
              Err("core module type mismatch")
            }
        }
      }
    _ =>
      if opts.best_effort {
        Ok(())
      } else {
        Err("core type index out of range")
      }
  }
}
