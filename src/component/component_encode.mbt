///|
fn append_bytes(dst : Array[Byte], src : Array[Byte]) -> Unit {
  for b in src {
    dst.push(b)
  }
}

///|
fn encode_u32_leb128(value : UInt) -> Array[Byte] {
  let mut v = value
  let out : Array[Byte] = []
  while true {
    let mut byte = (v & 0x7FU).to_byte()
    v = v >> 7
    if v != 0U {
      byte = (byte.to_uint() | 0x80U).to_byte()
      out.push(byte)
    } else {
      out.push(byte)
      break
    }
  }
  out
}

///|
fn append_name(dst : Array[Byte], name : Bytes) -> Unit {
  append_bytes(dst, encode_u32_leb128(name.length().reinterpret_as_uint()))
  for b in name {
    dst.push(b)
  }
}

///|
fn encode_externname(name : Bytes) -> Array[Byte] {
  let out : Array[Byte] = []
  out.push(0x00U.to_byte())
  append_name(out, name)
  out
}

///|
fn push_section(out : Array[Byte], id : UInt, payload : Array[Byte]) -> Unit {
  if payload.length() == 0 {
    return
  }
  out.push(id.to_byte())
  append_bytes(out, encode_u32_leb128(payload.length().reinterpret_as_uint()))
  append_bytes(out, payload)
}

///|
fn extern_kind_sort(kind : ExternKind) -> UInt? {
  match kind {
    Func => Some(0x01U)
    Value => Some(0x02U)
    Type => Some(0x03U)
    Component => Some(0x04U)
    Instance => Some(0x05U)
    CoreModule => None
  }
}

///|
fn append_extern_sort(dst : Array[Byte], kind : ExternKind) -> Unit {
  match extern_kind_sort(kind) {
    Some(v) => dst.push(v.to_byte())
    None => {
      dst.push(0x00U.to_byte())
      dst.push(0x11U.to_byte())
    }
  }
}

///|
fn encode_import(info : ImportInfo) -> Array[Byte] {
  let out : Array[Byte] = []
  append_bytes(out, encode_externname(info.name))
  append_bytes(out, info.raw_desc.to_array())
  out
}

///|
fn encode_export(name : Bytes, kind : ExternKind, idx : UInt) -> Array[Byte] {
  let out : Array[Byte] = []
  append_bytes(out, encode_externname(name))
  append_extern_sort(out, kind)
  append_bytes(out, encode_u32_leb128(idx))
  // externtypeopt: none
  out.push(0x00U.to_byte())
  out
}

///|
fn encode_alias(
  kind : ExternKind,
  instance_idx : UInt,
  name : Bytes,
) -> Array[Byte] {
  let out : Array[Byte] = []
  append_extern_sort(out, kind)
  // target: export
  out.push(0x00U.to_byte())
  append_bytes(out, encode_u32_leb128(instance_idx))
  append_name(out, name)
  out
}

///|
fn encode_instance(
  component_idx : UInt,
  args : Array[InstantiateArgEntry],
) -> Array[Byte] {
  let out : Array[Byte] = []
  // kind = instantiate
  out.push(0x00U.to_byte())
  append_bytes(out, encode_u32_leb128(component_idx))
  append_bytes(out, encode_u32_leb128(args.length().reinterpret_as_uint()))
  for arg in args {
    append_name(out, arg.name)
    append_extern_sort(out, arg.kind)
    append_bytes(out, encode_u32_leb128(arg.idx))
  }
  out
}

///|
priv struct InstantiateArgEntry {
  name : Bytes
  kind : ExternKind
  idx : UInt
}
