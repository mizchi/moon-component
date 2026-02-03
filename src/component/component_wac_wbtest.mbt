///|
test "inline import func type check" {
  let func_type : ComponentFuncType = {
    params: [
      { name: b"arg", type_: ComponentValType::Primitive(PrimitiveType::U32) },
    ],
    results: [],
  }
  let detail : ComponentDetail = {
    types: [ComponentTypeDef::Func(func_type)],
    imports: [
      {
        name: b"foo",
        kind: ExternKind::Func,
        type_ref: ComponentTypeRef::Func(0U),
      },
    ],
    exports: [],
    components: [],
    instances: [],
    imported_components: [],
    imported_instances: [],
    core_modules: [],
    core_types: [],
  }
  let import_detail = detail.imports[0]
  match
    check_inline_import_type(
      detail,
      "foo",
      import_detail,
      WacImportType::InlineFunc("func(arg: u32)"),
      false,
    ) {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "inline import func mismatch" {
  let func_type : ComponentFuncType = {
    params: [
      { name: b"arg", type_: ComponentValType::Primitive(PrimitiveType::U32) },
    ],
    results: [],
  }
  let detail : ComponentDetail = {
    types: [ComponentTypeDef::Func(func_type)],
    imports: [
      {
        name: b"foo",
        kind: ExternKind::Func,
        type_ref: ComponentTypeRef::Func(0U),
      },
    ],
    exports: [],
    components: [],
    instances: [],
    imported_components: [],
    imported_instances: [],
    core_modules: [],
    core_types: [],
  }
  let import_detail = detail.imports[0]
  let result = check_inline_import_type(
    detail,
    "foo",
    import_detail,
    WacImportType::InlineFunc("func(arg: u64)"),
    false,
  )
  guard result is Err(_) else { fail("expected mismatch") }
}

///|
test "inline import interface type check" {
  let func_type : ComponentFuncType = {
    params: [],
    results: [
      { name: None, type_: ComponentValType::Primitive(PrimitiveType::String) },
    ],
  }
  let inst_def : InstanceTypeDef = {
    exports: [{ name: b"greet", type_ref: ComponentTypeRef::Func(0U) }],
    entries: [InstanceTypeEntry::Local(ComponentTypeDef::Func(func_type))],
  }
  let detail : ComponentDetail = {
    types: [ComponentTypeDef::Instance(inst_def)],
    imports: [
      {
        name: b"iface",
        kind: ExternKind::Instance,
        type_ref: ComponentTypeRef::Instance(0U),
      },
    ],
    exports: [],
    components: [],
    instances: [],
    imported_components: [],
    imported_instances: [],
    core_modules: [],
    core_types: [],
  }
  let import_detail = detail.imports[0]
  match
    check_inline_import_type(
      detail,
      "iface",
      import_detail,
      WacImportType::InlineInterface("{ greet: func() -> string; }"),
      false,
    ) {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "inline import interface mismatch" {
  let func_type : ComponentFuncType = {
    params: [],
    results: [
      { name: None, type_: ComponentValType::Primitive(PrimitiveType::String) },
    ],
  }
  let inst_def : InstanceTypeDef = {
    exports: [{ name: b"greet", type_ref: ComponentTypeRef::Func(0U) }],
    entries: [InstanceTypeEntry::Local(ComponentTypeDef::Func(func_type))],
  }
  let detail : ComponentDetail = {
    types: [ComponentTypeDef::Instance(inst_def)],
    imports: [
      {
        name: b"iface",
        kind: ExternKind::Instance,
        type_ref: ComponentTypeRef::Instance(0U),
      },
    ],
    exports: [],
    components: [],
    instances: [],
    imported_components: [],
    imported_instances: [],
    core_modules: [],
    core_types: [],
  }
  let import_detail = detail.imports[0]
  let result = check_inline_import_type(
    detail,
    "iface",
    import_detail,
    WacImportType::InlineInterface("{ greet: func() -> u32; }"),
    false,
  )
  guard result is Err(_) else { fail("expected mismatch") }
}
