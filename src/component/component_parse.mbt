///|
/// Parse a component binary to extract import/export summaries.
pub fn parse_component_info(bytes : Bytes) -> Result[ComponentInfo, ParseError] {
  try? parse_component_info_raise(bytes)
}

///|
/// Parse a component binary to extract type-aware details.
pub fn parse_component_detail(
  bytes : Bytes,
) -> Result[ComponentDetail, ParseError] {
  try? parse_component_detail_raise(bytes)
}

///|
fn parse_component_info_raise(bytes : Bytes) -> ComponentInfo raise ParseError {
  let parser = Parser::new(bytes)

  // magic: \0asm
  let magic = parser.read_bytes(4)
  if magic[0].to_int() != 0x00 ||
    magic[1].to_int() != 0x61 ||
    magic[2].to_int() != 0x73 ||
    magic[3].to_int() != 0x6D {
    raise ParseError::InvalidMagic
  }

  // version: 0x0d 0x00 (component)
  let version = parser.read_bytes(2)
  if version[0].to_int() != 0x0d || version[1].to_int() != 0x00 {
    raise ParseError::UnsupportedVersion
  }

  // layer: 0x01 0x00
  let layer = parser.read_bytes(2)
  if layer[0].to_int() != 0x01 || layer[1].to_int() != 0x00 {
    raise ParseError::InvalidLayer
  }
  let imports : Array[ImportInfo] = []
  let exports : Array[ExportInfo] = []
  while not(parser.eof()) {
    let section_id = parser.read_byte().to_uint()
    let section_size = parser.read_u32_leb128()
    let section_start = parser.get_pos()
    match section_id {
      10 => {
        // import section
        let count = parser.read_u32_leb128()
        for _ in 0U..<count {
          let (name, _url) = parse_externname(parser)
          let (kind, raw_desc) = parse_externdesc_raw(parser)
          imports.push({ name, kind, raw_desc })
        }
      }
      11 => {
        // export section
        let count = parser.read_u32_leb128()
        for _ in 0U..<count {
          let (name, _url) = parse_externname(parser)
          let kind = parse_export_kind(parser)
          // externtypeopt: 0x00 = none, otherwise externdesc
          let externtypeopt = parser.read_byte().to_uint()
          if externtypeopt != 0x00 {
            // We already consumed the kind byte, so skip the rest
            skip_externdesc_with_kind(parser, externtypeopt)
          }
          exports.push({ name, kind })
        }
      }
      _ =>
        // skip other sections
        parser.set_pos(section_start + section_size.reinterpret_as_int())
    }
  }
  { imports, exports }
}

///|
fn parse_component_detail_raise(
  bytes : Bytes,
) -> ComponentDetail raise ParseError {
  let parser = Parser::new(bytes)

  // magic: \0asm
  let magic = parser.read_bytes(4)
  if magic[0].to_int() != 0x00 ||
    magic[1].to_int() != 0x61 ||
    magic[2].to_int() != 0x73 ||
    magic[3].to_int() != 0x6D {
    raise ParseError::InvalidMagic
  }

  // version: 0x0d 0x00 (component)
  let version = parser.read_bytes(2)
  if version[0].to_int() != 0x0d || version[1].to_int() != 0x00 {
    raise ParseError::UnsupportedVersion
  }

  // layer: 0x01 0x00
  let layer = parser.read_bytes(2)
  if layer[0].to_int() != 0x01 || layer[1].to_int() != 0x00 {
    raise ParseError::InvalidLayer
  }
  let types : Array[ComponentTypeDef] = []
  let imports : Array[ComponentImportDetail] = []
  let exports : Array[ComponentExportDetail] = []
  let components : Array[Bytes] = []
  let instances : Array[ComponentInstanceDef] = []
  let imported_components : Array[ComponentTypeRef] = []
  let imported_instances : Array[ComponentTypeRef] = []
  while not(parser.eof()) {
    let section_id = parser.read_byte().to_uint()
    let section_size = parser.read_u32_leb128()
    let section_start = parser.get_pos()
    let section_end = section_start + section_size.reinterpret_as_int()
    match section_id {
      4 => {
        let comp_bytes = parser.slice(section_start, section_end)
        components.push(comp_bytes)
        parser.set_pos(section_end)
      }
      5 => {
        let count = parser.read_u32_leb128()
        for _ in 0U..<count {
          instances.push(parse_component_instance(parser))
        }
      }
      7 => {
        let count = parser.read_u32_leb128()
        for _ in 0U..<count {
          types.push(parse_component_type(parser))
        }
      }
      10 => {
        let count = parser.read_u32_leb128()
        for _ in 0U..<count {
          let name = parse_component_name(parser)
          let type_ref = parse_component_type_ref(parser)
          let kind = extern_kind_of_type_ref(type_ref)
          let detail = { name, kind, type_ref }
          if kind == ExternKind::Component {
            imported_components.push(type_ref)
          } else if kind == ExternKind::Instance {
            imported_instances.push(type_ref)
          }
          imports.push(detail)
        }
      }
      11 => {
        let count = parser.read_u32_leb128()
        for _ in 0U..<count {
          let name = parse_component_name(parser)
          let kind = parse_component_external_kind(parser)
          let index = parser.read_u32_leb128()
          let type_ref = match parser.read_byte().to_uint() {
            0x00 => None
            0x01 => Some(parse_component_type_ref(parser))
            _ => raise ParseError::InvalidFormat("invalid export type option")
          }
          exports.push({ name, kind, index, type_ref })
        }
      }
      _ => parser.set_pos(section_end)
    }
    if parser.get_pos() < section_end {
      parser.set_pos(section_end)
    }
  }
  {
    types,
    imports,
    exports,
    components,
    instances,
    imported_components,
    imported_instances,
  }
}

///|
fn parse_externname(parser : Parser) -> (Bytes, Bytes?) raise ParseError {
  let name_kind = parser.read_byte().to_uint()
  match name_kind {
    0x00 => (parser.read_name(), None) // kebab-name
    0x01 => {
      let url_bytes = parser.read_name()
      (url_bytes, Some(url_bytes))
    }
    0x02 => (parser.read_name(), None)
    0x03 => {
      let hash_len = parser.read_u32_leb128()
      for _ in 0U..<hash_len {
        let _ = parser.read_byte()

      }
      (parser.read_name(), None)
    }
    0x04 => {
      let hash_len = parser.read_u32_leb128()
      for _ in 0U..<hash_len {
        let _ = parser.read_byte()

      }
      (parser.read_name(), None)
    }
    _ =>
      raise ParseError::InvalidFormat(
        "invalid externname kind: 0x\{name_kind.to_string()}",
      )
  }
}

///|
fn parse_component_name(parser : Parser) -> Bytes raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 | 0x01 => parser.read_name()
    _ =>
      raise ParseError::InvalidFormat(
        "invalid component name discriminator: 0x\{kind.to_string()}",
      )
  }
}

///|
fn parse_component_external_kind(
  parser : Parser,
) -> ExternKind raise ParseError {
  let first = parser.read_byte().to_uint()
  match first {
    0x00 => {
      let second = parser.read_byte().to_uint()
      if second != 0x11 {
        raise ParseError::InvalidFormat(
          "invalid core module kind: 0x\{second.to_string()}",
        )
      }
      ExternKind::CoreModule
    }
    0x01 => ExternKind::Func
    0x02 => ExternKind::Value
    0x03 => ExternKind::Type
    0x04 => ExternKind::Component
    0x05 => ExternKind::Instance
    _ =>
      raise ParseError::InvalidFormat(
        "invalid component external kind: 0x\{first.to_string()}",
      )
  }
}

///|
fn extern_kind_of_type_ref(type_ref : ComponentTypeRef) -> ExternKind {
  match type_ref {
    ComponentTypeRef::Module(_) => ExternKind::CoreModule
    ComponentTypeRef::Func(_) => ExternKind::Func
    ComponentTypeRef::Value(_) => ExternKind::Value
    ComponentTypeRef::Type(_) => ExternKind::Type
    ComponentTypeRef::Component(_) => ExternKind::Component
    ComponentTypeRef::Instance(_) => ExternKind::Instance
  }
}

///|
fn parse_component_type_ref(
  parser : Parser,
) -> ComponentTypeRef raise ParseError {
  let kind = parse_component_external_kind(parser)
  match kind {
    ExternKind::CoreModule => ComponentTypeRef::Module(parser.read_u32_leb128())
    ExternKind::Func => ComponentTypeRef::Func(parser.read_u32_leb128())
    ExternKind::Value =>
      ComponentTypeRef::Value(parse_component_valtype(parser))
    ExternKind::Type => ComponentTypeRef::Type(parse_type_bounds(parser))
    ExternKind::Component =>
      ComponentTypeRef::Component(parser.read_u32_leb128())
    ExternKind::Instance => ComponentTypeRef::Instance(parser.read_u32_leb128())
  }
}

///|
fn parse_component_instance(
  parser : Parser,
) -> ComponentInstanceDef raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => {
      let component_index = parser.read_u32_leb128()
      let arg_count = parser.read_u32_leb128()
      for _ in 0U..<arg_count {
        let _ = parser.read_name()
        let _ = parse_component_external_kind(parser)
        let _ = parser.read_u32_leb128()

      }
      ComponentInstanceDef::Instantiate(component_index)
    }
    0x01 => {
      let export_count = parser.read_u32_leb128()
      let exports : Array[ExportInfo] = []
      for _ in 0U..<export_count {
        let name = parse_component_name(parser)
        let kind = parse_component_external_kind(parser)
        let _ = parser.read_u32_leb128()
        exports.push({ name, kind })
      }
      ComponentInstanceDef::FromExports(exports)
    }
    _ => raise ParseError::InvalidFormat("invalid instance kind")
  }
}

///|
fn parse_component_type(parser : Parser) -> ComponentTypeDef raise ParseError {
  let tag = parser.read_byte().to_uint()
  match tag {
    0x3F => {
      let _ = parser.read_byte()
      match parser.read_byte().to_uint() {
        0x00 => ()
        0x01 => {
          let _ = parser.read_u32_leb128()

        }
        _ => raise ParseError::InvalidFormat("invalid resource destructor")
      }
      ComponentTypeDef::Resource
    }
    0x40 | 0x43 => {
      let param_count = parser.read_u32_leb128()
      let params : Array[ComponentParam] = []
      for _ in 0U..<param_count {
        let name = parser.read_name()
        let ty = parse_component_valtype(parser)
        params.push({ name, type_: ty })
      }
      let result = parse_component_result(parser)
      let results : Array[ComponentResult] = []
      match result {
        Some(ty) => results.push({ name: None, type_: ty })
        None => ()
      }
      ComponentTypeDef::Func({ params, results })
    }
    0x41 => {
      let decl_count = parser.read_u32_leb128()
      for _ in 0U..<decl_count {
        skip_component_type_decl(parser)
      }
      ComponentTypeDef::Component
    }
    0x42 => {
      let decl_count = parser.read_u32_leb128()
      let exports : Array[InstanceExport] = []
      let entries : Array[InstanceTypeEntry] = []
      for _ in 0U..<decl_count {
        let decl_kind = parser.read_byte().to_uint()
        match decl_kind {
          0x00 => skip_core_type(parser)
          0x01 => {
            let ty = parse_component_type(parser)
            entries.push(InstanceTypeEntry::Local(ty))
          }
          0x02 => {
            let entry = parse_instance_alias(parser)
            entries.push(entry)
          }
          0x04 => {
            let name = parse_component_name(parser)
            let type_ref = parse_component_type_ref(parser)
            exports.push({ name, type_ref })
          }
          _ => raise ParseError::InvalidFormat("invalid instance type decl")
        }
      }
      ComponentTypeDef::Instance({ exports, entries })
    }
    _ => {
      let ty = parse_component_valtype_with_tag(
        parser,
        tag.reinterpret_as_int(),
      )
      ComponentTypeDef::Defined(ty)
    }
  }
}

///|
fn parse_component_result(
  parser : Parser,
) -> ComponentValType? raise ParseError {
  let tag = parser.read_byte().to_uint()
  match tag {
    0x00 => Some(parse_component_valtype(parser))
    0x01 => {
      let next = parser.read_byte().to_uint()
      if next != 0x00 {
        raise ParseError::InvalidFormat("invalid component result list")
      }
      None
    }
    _ => raise ParseError::InvalidFormat("invalid component result list")
  }
}

///|
fn parse_component_valtype(
  parser : Parser,
) -> ComponentValType raise ParseError {
  let pos = parser.get_pos()
  let byte = parser.read_byte()
  parse_component_valtype_with_tag(parser, byte.to_int()) catch {
    _ => {
      parser.set_pos(pos)
      let idx = parser.read_i32_leb128()
      if idx < 0 {
        raise ParseError::InvalidFormat("invalid component val type")
      }
      ComponentValType::TypeIndex(idx.reinterpret_as_uint())
    }
  }
}

///|
fn parse_component_valtype_with_tag(
  parser : Parser,
  kind : Int,
) -> ComponentValType raise ParseError {
  match kind {
    0x7F => ComponentValType::Primitive(PrimitiveType::Bool)
    0x7E => ComponentValType::Primitive(PrimitiveType::S8)
    0x7D => ComponentValType::Primitive(PrimitiveType::U8)
    0x7C => ComponentValType::Primitive(PrimitiveType::S16)
    0x7B => ComponentValType::Primitive(PrimitiveType::U16)
    0x7A => ComponentValType::Primitive(PrimitiveType::S32)
    0x79 => ComponentValType::Primitive(PrimitiveType::U32)
    0x78 => ComponentValType::Primitive(PrimitiveType::S64)
    0x77 => ComponentValType::Primitive(PrimitiveType::U64)
    0x76 => ComponentValType::Primitive(PrimitiveType::F32)
    0x75 => ComponentValType::Primitive(PrimitiveType::F64)
    0x74 => ComponentValType::Primitive(PrimitiveType::Char)
    0x73 => ComponentValType::Primitive(PrimitiveType::String)
    0x72 => {
      let field_count = parser.read_u32_leb128()
      let fields : Array[RecordField] = []
      for _ in 0U..<field_count {
        let name = parser.read_name()
        let ty = parse_component_valtype(parser)
        fields.push({ name, type_: ty })
      }
      ComponentValType::Record(fields)
    }
    0x71 => {
      let case_count = parser.read_u32_leb128()
      let cases : Array[VariantCase] = []
      for _ in 0U..<case_count {
        let name = parser.read_name()
        let has_type = parser.read_byte().to_uint()
        let ty = if has_type == 0x01 {
          Some(parse_component_valtype(parser))
        } else {
          None
        }
        let has_refines = parser.read_byte().to_uint()
        let refines = if has_refines == 0x01 {
          Some(parser.read_u32_leb128())
        } else {
          None
        }
        cases.push({ name, type_: ty, refines })
      }
      ComponentValType::Variant(cases)
    }
    0x70 => ComponentValType::List(parse_component_valtype(parser))
    0x6F => {
      let type_count = parser.read_u32_leb128()
      let types : Array[ComponentValType] = []
      for _ in 0U..<type_count {
        types.push(parse_component_valtype(parser))
      }
      ComponentValType::Tuple(types)
    }
    0x6E => {
      let flag_count = parser.read_u32_leb128()
      let flags : Array[Bytes] = []
      for _ in 0U..<flag_count {
        flags.push(parser.read_name())
      }
      ComponentValType::Flags(flags)
    }
    0x6D => {
      let case_count = parser.read_u32_leb128()
      let cases : Array[Bytes] = []
      for _ in 0U..<case_count {
        cases.push(parser.read_name())
      }
      ComponentValType::Enum(cases)
    }
    0x6B => ComponentValType::Option(parse_component_valtype(parser))
    0x6A => {
      let has_ok = parser.read_byte().to_uint()
      let ok = if has_ok == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      let has_err = parser.read_byte().to_uint()
      let err = if has_err == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      ComponentValType::Result(ok, err)
    }
    0x69 => ComponentValType::Own(parser.read_u32_leb128())
    0x68 => ComponentValType::Borrow(parser.read_u32_leb128())
    0x67 => {
      let ty = parse_component_valtype(parser)
      let len = parser.read_u32_leb128()
      ComponentValType::FixedSizeList(ty, len)
    }
    0x66 => {
      let has_type = parser.read_byte().to_uint()
      let ty = if has_type == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      ComponentValType::Stream(ty)
    }
    0x65 => {
      let has_type = parser.read_byte().to_uint()
      let ty = if has_type == 0x01 {
        Some(parse_component_valtype(parser))
      } else {
        None
      }
      ComponentValType::Future(ty)
    }
    0x64 => ComponentValType::ErrorContext
    0x63 => {
      let key = parse_component_valtype(parser)
      let value = parse_component_valtype(parser)
      ComponentValType::Map(key, value)
    }
    _ => raise ParseError::InvalidFormat("invalid component val type")
  }
}

///|
fn parse_type_bounds(parser : Parser) -> TypeBounds raise ParseError {
  match parser.read_byte().to_uint() {
    0x00 => TypeBounds::Eq(parser.read_u32_leb128())
    0x01 => TypeBounds::SubResource
    _ => raise ParseError::InvalidFormat("invalid type bounds kind")
  }
}

///|
fn skip_component_type_decl(parser : Parser) -> Unit raise ParseError {
  match parser.peek_byte() {
    Some(b) =>
      if b.to_uint() == 0x03U {
        let _ = parser.read_byte()
        let _ = parse_component_name(parser)
        let _ = parse_component_type_ref(parser)
        return
      }
    None => raise ParseError::UnexpectedEof
  }
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => skip_core_type(parser)
    0x01 => {
      let _ = parse_component_type(parser)

    }
    0x02 => skip_component_alias(parser)
    0x04 => {
      let _ = parse_component_name(parser)
      let _ = parse_component_type_ref(parser)

    }
    _ => raise ParseError::InvalidFormat("invalid component type decl")
  }
}

///|
fn skip_component_alias(parser : Parser) -> Unit raise ParseError {
  let first = parser.read_byte().to_uint()
  let second = if first == 0x00 {
    Some(parser.read_byte().to_uint())
  } else {
    None
  }
  let _ = second
  let target = parser.read_byte().to_uint()
  match target {
    0x00 => {
      let _ = parser.read_u32_leb128()
      let _ = parser.read_name()

    }
    0x01 => {
      let _ = parser.read_u32_leb128()
      let _ = parser.read_name()

    }
    0x02 => {
      let _ = parser.read_u32_leb128()
      let _ = parser.read_u32_leb128()

    }
    _ => raise ParseError::InvalidFormat("invalid alias target")
  }
}

///|
fn parse_instance_alias(parser : Parser) -> InstanceTypeEntry raise ParseError {
  let first = parser.read_byte().to_uint()
  let second = if first == 0x00 {
    Some(parser.read_byte().to_uint())
  } else {
    None
  }
  let kind_is_type = first == 0x03
  let _ = second
  let target = parser.read_byte().to_uint()
  match target {
    0x00 => {
      let instance_idx = parser.read_u32_leb128()
      let name = parser.read_name()
      if kind_is_type {
        InstanceTypeEntry::Alias(
          InstanceAliasTarget::Export(instance_idx, name),
        )
      } else {
        InstanceTypeEntry::Alias(InstanceAliasTarget::Unknown)
      }
    }
    0x01 => {
      let _ = parser.read_u32_leb128()
      let _ = parser.read_name()
      InstanceTypeEntry::Alias(InstanceAliasTarget::Unknown)
    }
    0x02 => {
      let count = parser.read_u32_leb128()
      let index = parser.read_u32_leb128()
      if kind_is_type {
        InstanceTypeEntry::Alias(InstanceAliasTarget::Outer(count, index))
      } else {
        InstanceTypeEntry::Alias(InstanceAliasTarget::Unknown)
      }
    }
    _ => raise ParseError::InvalidFormat("invalid alias target")
  }
}

///|
fn skip_core_type(parser : Parser) -> Unit raise ParseError {
  let kind = match parser.peek_byte() {
    Some(b) => b.to_uint()
    None => raise ParseError::UnexpectedEof
  }
  if kind == 0x50 {
    let _ = parser.read_byte()
    let decl_count = parser.read_u32_leb128()
    for _ in 0U..<decl_count {
      let decl = parser.read_byte().to_uint()
      match decl {
        0x00 => {
          let _ = parser.read_name()
          let _ = parser.read_byte()
          let _ = parser.read_u32_leb128()

        }
        0x01 => skip_rec_group(parser)
        0x02 => {
          let _ = parser.read_byte()
          let _ = parser.read_u32_leb128()
          let _ = parser.read_u32_leb128()

        }
        0x03 => {
          let _ = parser.read_name()
          let _ = parser.read_byte()
          let _ = parser.read_u32_leb128()

        }
        _ => raise ParseError::InvalidFormat("invalid core type decl")
      }
    }
  } else {
    skip_rec_group(parser)
  }
}

///|
fn skip_rec_group(parser : Parser) -> Unit raise ParseError {
  let kind = match parser.peek_byte() {
    Some(b) => b.to_uint()
    None => raise ParseError::UnexpectedEof
  }
  if kind == 0x4F {
    let _ = parser.read_byte()
    let count = parser.read_u32_leb128()
    for _ in 0U..<count {
      skip_sub_type(parser)
    }
  } else {
    skip_sub_type(parser)
  }
}

///|
fn skip_sub_type(parser : Parser) -> Unit raise ParseError {
  let _ = parser.read_byte()
  skip_core_func_type(parser)
}

///|
fn skip_core_func_type(parser : Parser) -> Unit raise ParseError {
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
fn parse_export_kind(parser : Parser) -> ExternKind raise ParseError {
  let sort_kind = parser.read_byte().to_uint()
  if sort_kind == 0x00 {
    let core_sort = parser.read_byte().to_uint()
    let _idx = parser.read_u32_leb128()
    match core_sort {
      0x11 => ExternKind::CoreModule
      _ =>
        raise ParseError::InvalidFormat(
          "invalid core export sort: 0x\{core_sort.to_string()}",
        )
    }
  } else {
    let _idx = parser.read_u32_leb128()
    match sort_kind {
      0x01 => ExternKind::Func
      0x02 => ExternKind::Value
      0x03 => ExternKind::Type
      0x04 => ExternKind::Component
      0x05 => ExternKind::Instance
      _ =>
        raise ParseError::InvalidFormat(
          "invalid export sort kind: 0x\{sort_kind.to_string()}",
        )
    }
  }
}

///|
fn parse_externdesc_raw(
  parser : Parser,
) -> (ExternKind, Bytes) raise ParseError {
  let start = parser.get_pos()
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => {
      let sub_kind = parser.read_byte().to_uint()
      if sub_kind != 0x11 {
        raise ParseError::InvalidFormat(
          "expected 0x11 for core module externdesc, got 0x\{sub_kind.to_string()}",
        )
      }
      let _ = parser.read_u32_leb128()

    }
    0x01 => {
      let _ = parser.read_u32_leb128()

    }
    0x02 => {
      let _ = skip_component_valtype(parser)

    }
    0x03 => {
      let _ = skip_type_bounds(parser)

    }
    0x04 => {
      let _ = parser.read_u32_leb128()

    }
    0x05 => {
      let _ = parser.read_u32_leb128()

    }
    _ => raise ParseError::InvalidFormat("invalid extern desc kind")
  }
  let end = parser.get_pos()
  let raw = parser.slice(start, end)
  let kind_enum = match kind {
    0x00 => ExternKind::CoreModule
    0x01 => ExternKind::Func
    0x02 => ExternKind::Value
    0x03 => ExternKind::Type
    0x04 => ExternKind::Component
    0x05 => ExternKind::Instance
    _ => ExternKind::Func
  }
  (kind_enum, raw)
}

///|
fn skip_externdesc_with_kind(
  parser : Parser,
  kind : UInt,
) -> Unit raise ParseError {
  match kind {
    0x00 => {
      let sub_kind = parser.read_byte().to_uint()
      if sub_kind != 0x11 {
        raise ParseError::InvalidFormat(
          "expected 0x11 for core module externdesc, got 0x\{sub_kind.to_string()}",
        )
      }
      let _ = parser.read_u32_leb128()

    }
    0x01 => {
      let _ = parser.read_u32_leb128()

    }
    0x02 => {
      let _ = skip_component_valtype(parser)

    }
    0x03 => {
      let _ = skip_type_bounds(parser)

    }
    0x04 => {
      let _ = parser.read_u32_leb128()

    }
    0x05 => {
      let _ = parser.read_u32_leb128()

    }
    _ => raise ParseError::InvalidFormat("invalid extern desc kind")
  }
}

///|
fn skip_type_bounds(parser : Parser) -> Unit raise ParseError {
  let kind = parser.read_byte().to_uint()
  match kind {
    0x00 => {
      let _ = parser.read_u32_leb128()

    }
    0x01 => ()
    _ => raise ParseError::InvalidFormat("invalid type bounds kind")
  }
}

///|
fn skip_component_valtype(parser : Parser) -> Unit raise ParseError {
  let byte = parser.read_byte()
  let kind = byte.to_int()
  match kind {
    0x7F
    | 0x7E
    | 0x7D
    | 0x7C
    | 0x7B
    | 0x7A
    | 0x79
    | 0x78
    | 0x77
    | 0x76
    | 0x75
    | 0x74
    | 0x73 => ()
    0x72 => {
      let field_count = parser.read_u32_leb128()
      for _ in 0U..<field_count {
        let _ = parser.read_name()
        skip_component_valtype(parser)
      }
    }
    0x71 => {
      let case_count = parser.read_u32_leb128()
      for _ in 0U..<case_count {
        let _ = parser.read_name()
        let has_type = parser.read_byte().to_uint()
        if has_type == 0x01 {
          skip_component_valtype(parser)
        }
        let has_refines = parser.read_byte().to_uint()
        if has_refines == 0x01 {
          let _ = parser.read_u32_leb128()

        }
      }
    }
    0x70 => skip_component_valtype(parser)
    0x6F => {
      let type_count = parser.read_u32_leb128()
      for _ in 0U..<type_count {
        skip_component_valtype(parser)
      }
    }
    0x6E => {
      let flag_count = parser.read_u32_leb128()
      for _ in 0U..<flag_count {
        let _ = parser.read_name()

      }
    }
    0x6D => {
      let case_count = parser.read_u32_leb128()
      for _ in 0U..<case_count {
        let _ = parser.read_name()

      }
    }
    0x6B => skip_component_valtype(parser)
    0x6A => {
      let has_ok = parser.read_byte().to_uint()
      if has_ok == 0x01 {
        skip_component_valtype(parser)
      }
      let has_err = parser.read_byte().to_uint()
      if has_err == 0x01 {
        skip_component_valtype(parser)
      }
    }
    0x69 => {
      let _ = parser.read_u32_leb128()

    }
    0x68 => {
      let _ = parser.read_u32_leb128()

    }
    0x67 => {
      skip_component_valtype(parser)
      let _ = parser.read_u32_leb128()

    }
    0x66 => {
      let has_type = parser.read_byte().to_uint()
      if has_type == 0x01 {
        skip_component_valtype(parser)
      }
    }
    0x65 => {
      let has_type = parser.read_byte().to_uint()
      if has_type == 0x01 {
        skip_component_valtype(parser)
      }
    }
    0x64 => ()
    _ => {
      parser.set_pos(parser.get_pos() - 1)
      let idx = parser.read_i32_leb128()
      if idx < 0 {
        raise ParseError::InvalidFormat("invalid component val type")
      }
      let _ = idx

    }
  }
}
