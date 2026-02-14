///|
/// Test to_camel_case conversion
test "to_camel_case" {
  inspect(to_camel_case("hello-world"), content="HelloWorld")
  inspect(to_camel_case("add-points"), content="AddPoints")
  inspect(to_camel_case("get_items"), content="GetItems")
  inspect(to_camel_case("parse-int"), content="ParseInt")
  inspect(to_camel_case("simple"), content="Simple")
}

///|
/// Test to_snake_case conversion
test "to_snake_case" {
  inspect(to_snake_case("hello-world"), content="hello_world")
  inspect(to_snake_case("add-points"), content="add_points")
  inspect(to_snake_case("simple"), content="simple")
}

///|
/// Test to_pascal_case conversion
test "to_pascal_case" {
  inspect(to_pascal_case("point"), content="Point")
  inspect(to_pascal_case("my-type"), content="MyType")
}

///|
/// Test GeneratorOpts default values
test "generator_opts_default" {
  let opts = GeneratorOpts::default()
  inspect(opts.trait_exports, content="true")
  inspect(opts.gen_dir, content="gen")
  inspect(opts.impl_dir, content="impl")
  inspect(opts.generate_impl, content="true")
  inspect(opts.generate_wkg, content="false")
  inspect(opts.generate_wite, content="false")
  inspect(opts.wkg_version, content="0.1.0")
}

///|
/// Test detect_dependencies with external imports
test "detect_dependencies" {
  // Create a resolve with two packages
  let iref : @resolve.InterfaceRef = { id: 0 }
  let world : @resolve.World = {
    name: "my-world",
    imports: { "http": @resolve.WorldItem::Interface(iref) },
    exports: {},
    pkg: Some(1), // my package
  }
  let iface : @resolve.Interface = {
    name: Some("handler"),
    functions: {},
    types: {},
    pkg: Some(0), // wasi package (external)
  }
  let pkg_name1 : @resolve.PackageName = {
    ns: "wasi",
    name: "http",
    version: Some("0.2.0"),
  }
  let pkg1 : @resolve.Package = {
    name: pkg_name1,
    interfaces: { "handler": 0 },
    worlds: {},
  }
  let pkg_name2 : @resolve.PackageName = {
    ns: "my",
    name: "app",
    version: None,
  }
  let pkg2 : @resolve.Package = {
    name: pkg_name2,
    interfaces: {},
    worlds: { "my-world": 0 },
  }
  let resolve : @resolve.Resolve = {
    worlds: [world],
    interfaces: [iface],
    types: [],
    packages: [pkg1, pkg2],
  }
  let opts = GeneratorOpts::default()
  let gen = Generator::new(resolve, 0, opts)
  let deps = gen.detect_dependencies(resolve.worlds[0])
  inspect(deps.length(), content="1")
  inspect(deps[0].ns, content="wasi")
  inspect(deps[0].name, content="http")
  inspect(deps[0].version, content="Some(\"0.2.0\")")
}

///|
/// Test generate_wite_config output format
test "generate_wite_config" {
  // Create a resolve with external dependency
  let iref : @resolve.InterfaceRef = { id: 0 }
  let world : @resolve.World = {
    name: "my-world",
    imports: { "http": @resolve.WorldItem::Interface(iref) },
    exports: {},
    pkg: Some(1),
  }
  let iface : @resolve.Interface = {
    name: Some("handler"),
    functions: {},
    types: {},
    pkg: Some(0),
  }
  let pkg_name1 : @resolve.PackageName = {
    ns: "wasi",
    name: "http",
    version: Some("0.2.0"),
  }
  let pkg1 : @resolve.Package = {
    name: pkg_name1,
    interfaces: { "handler": 0 },
    worlds: {},
  }
  let pkg_name2 : @resolve.PackageName = {
    ns: "my",
    name: "app",
    version: None,
  }
  let pkg2 : @resolve.Package = {
    name: pkg_name2,
    interfaces: {},
    worlds: { "my-world": 0 },
  }
  let resolve : @resolve.Resolve = {
    worlds: [world],
    interfaces: [iface],
    types: [],
    packages: [pkg1, pkg2],
  }
  let opts = GeneratorOpts::default()
  let gen = Generator::new(resolve, 0, opts)
  gen.generate_wite_config(resolve.worlds[0])
  // Find the wite.config.jsonc in output
  let mut found = false
  for file in gen.output {
    if file.path == "wite.config.jsonc" {
      found = true
      inspect(file.is_stub, content="true")
      // Check that deps contain wasi:http
      inspect(
        file.content.contains(
          "\"wasi:http\": \"https://wa.dev/wasi:http@0.2.0\"",
        ),
        content="true",
      )
      // Check build config present
      inspect(
        file.content.contains(
          "\"build\": { \"kind\": \"component\", \"flags\": [\"-Oz\"] }",
        ),
        content="true",
      )
    }
  }
  inspect(found, content="true")
}

///|
/// Test generate_wite_config with no deps
test "generate_wite_config_no_deps" {
  let world : @resolve.World = {
    name: "my-world",
    imports: {},
    exports: {},
    pkg: Some(0),
  }
  let pkg_name : @resolve.PackageName = { ns: "my", name: "app", version: None }
  let pkg : @resolve.Package = {
    name: pkg_name,
    interfaces: {},
    worlds: { "my-world": 0 },
  }
  let resolve : @resolve.Resolve = {
    worlds: [world],
    interfaces: [],
    types: [],
    packages: [pkg],
  }
  let opts = GeneratorOpts::default()
  let gen = Generator::new(resolve, 0, opts)
  gen.generate_wite_config(resolve.worlds[0])
  let mut found = false
  for file in gen.output {
    if file.path == "wite.config.jsonc" {
      found = true
      inspect(file.content.contains("\"deps\": {}"), content="true")
    }
  }
  inspect(found, content="true")
}

// ===== Import codegen tests =====

///|
/// Helper: build a Generator for import codegen tests
/// Creates a minimal resolve with one interface containing the given function and types
fn make_import_gen(
  types : Array[@resolve.TypeDef],
  func : @resolve.Function,
) -> Generator {
  let iref : @resolve.InterfaceRef = { id: 0 }
  let world : @resolve.World = {
    name: "test-world",
    imports: { "api": @resolve.WorldItem::Interface(iref) },
    exports: {},
    pkg: Some(0),
  }
  let type_map : Map[String, Int] = {}
  for i, td in types {
    match td.name {
      Some(n) => type_map[n] = i
      None => ()
    }
  }
  let func_map : Map[String, @resolve.Function] = {}
  func_map[func.name] = func
  let iface : @resolve.Interface = {
    name: Some("api"),
    functions: func_map,
    types: type_map,
    pkg: Some(0),
  }
  let pkg_name : @resolve.PackageName = {
    ns: "test",
    name: "pkg",
    version: Some("0.1.0"),
  }
  let pkg : @resolve.Package = {
    name: pkg_name,
    interfaces: { "api": 0 },
    worlds: { "test-world": 0 },
  }
  let resolve : @resolve.Resolve = {
    worlds: [world],
    interfaces: [iface],
    types,
    packages: [pkg],
  }
  let opts = GeneratorOpts::default()
  Generator::new(resolve, 0, opts)
}

///|
/// Helper: extract the import.mbt content from generator output
fn get_import_content(gen : Generator) -> String {
  for file in gen.output {
    if file.path.has_suffix("import.mbt") {
      return file.content
    }
  }
  abort("import.mbt not found in output")
}

///|
/// Test import_retptr_size: variant with f64 payload → size 16 (disc 1 + pad 7 + f64 8)
test "import_retptr_size_variant_f64" {
  // variant value { val-null, val-int(s32), val-float(f64) }
  let typedef : @resolve.TypeDef = {
    name: Some("value"),
    kind: Variant(
      [
        { name: "val-null", case_type: None },
        { name: "val-int", case_type: Some(S32) },
        { name: "val-float", case_type: Some(F64) },
      ],
    ),
    owner: @resolve.TypeOwner::Interface(0),
  }
  let func : @resolve.Function = {
    name: "get-value",
    kind: Freestanding,
    params: [],
    result: Some(Id(0)),
  }
  let gen = make_import_gen([typedef], func)
  // disc_size(3) = 1, max_payload_align = 8(f64), payload_offset = align_to(1, 8) = 8
  // total = 8 + 8 = 16
  inspect(gen.import_retptr_size(Id(0)), content="16")
}

///|
/// Test import_retptr_size: variant with only s32 payloads → size 8 (disc 1 + pad 3 + s32 4)
test "import_retptr_size_variant_s32" {
  let typedef : @resolve.TypeDef = {
    name: Some("op"),
    kind: Variant(
      [
        { name: "add", case_type: Some(S32) },
        { name: "sub", case_type: Some(S32) },
        { name: "nop", case_type: None },
      ],
    ),
    owner: @resolve.TypeOwner::Interface(0),
  }
  let func : @resolve.Function = {
    name: "get-op",
    kind: Freestanding,
    params: [],
    result: Some(Id(0)),
  }
  let gen = make_import_gen([typedef], func)
  // disc_size(3) = 1, max_payload_align = 4(s32), payload_offset = align_to(1, 4) = 4
  // total = 4 + 4 = 8
  inspect(gen.import_retptr_size(Id(0)), content="8")
}

///|
/// Test import_retptr_size: option<f64> → size 16 (disc 1 + pad 7 + f64 8)
test "import_retptr_size_option_f64" {
  let typedef : @resolve.TypeDef = {
    name: Some("opt-f64"),
    kind: Option(F64),
    owner: @resolve.TypeOwner::Interface(0),
  }
  let func : @resolve.Function = {
    name: "get-opt",
    kind: Freestanding,
    params: [],
    result: Some(Id(0)),
  }
  let gen = make_import_gen([typedef], func)
  inspect(gen.import_retptr_size(Id(0)), content="16")
}

///|
/// Test import_retptr_size: option<s32> → size 8 (disc 1 + pad 3 + s32 4)
test "import_retptr_size_option_s32" {
  let typedef : @resolve.TypeDef = {
    name: Some("opt-s32"),
    kind: Option(S32),
    owner: @resolve.TypeOwner::Interface(0),
  }
  let func : @resolve.Function = {
    name: "get-opt",
    kind: Freestanding,
    params: [],
    result: Some(Id(0)),
  }
  let gen = make_import_gen([typedef], func)
  inspect(gen.import_retptr_size(Id(0)), content="8")
}

///|
/// Test import_retptr_size: result<f64, s32> → size 16 (disc 1 + pad 7 + max(f64,s32) = f64 8)
test "import_retptr_size_result_f64_s32" {
  let typedef : @resolve.TypeDef = {
    name: Some("res"),
    kind: Result(ok=Some(F64), err=Some(S32)),
    owner: @resolve.TypeOwner::Interface(0),
  }
  let func : @resolve.Function = {
    name: "get-res",
    kind: Freestanding,
    params: [],
    result: Some(Id(0)),
  }
  let gen = make_import_gen([typedef], func)
  inspect(gen.import_retptr_size(Id(0)), content="16")
}

///|
/// Test import codegen: variant return uses cabi_read_u8 for discriminant and offset 8 for f64 payload
test "import_codegen_variant_return_layout" {
  // variant value { val-null, val-bool(bool), val-int(s32), val-float(f64), val-str(string) }
  let typedef : @resolve.TypeDef = {
    name: Some("value"),
    kind: Variant(
      [
        { name: "val-null", case_type: None },
        { name: "val-bool", case_type: Some(Bool) },
        { name: "val-int", case_type: Some(S32) },
        { name: "val-float", case_type: Some(F64) },
        { name: "val-str", case_type: Some(String_) },
      ],
    ),
    owner: @resolve.TypeOwner::Interface(0),
  }
  let func : @resolve.Function = {
    name: "compute",
    kind: Freestanding,
    params: [("key", String_)],
    result: Some(Id(0)),
  }
  let gen = make_import_gen([typedef], func)
  gen.generate_interface_import(0)
  let content = get_import_content(gen)
  // Discriminant must be read as u8 (≤256 cases)
  inspect(content.contains("cabi_read_u8(retptr).to_int()"), content="true")
  // Payload must be at offset 8 (aligned to f64)
  inspect(content.contains("cabi_read_i32(retptr + 8)"), content="true")
  inspect(content.contains("cabi_read_f64(retptr + 8)"), content="true")
  // Retptr size must be 16
  inspect(content.contains("cabi_realloc(0, 0, 4, 16)"), content="true")
  // Must NOT use cabi_read_i32(retptr) for discriminant
  inspect(content.contains("cabi_read_i32(retptr)"), content="false")
}

///|
/// Test import codegen: option<s32> return uses u8 disc and correct offset
test "import_codegen_option_return_layout" {
  let typedef : @resolve.TypeDef = {
    name: Some("opt"),
    kind: Option(S32),
    owner: @resolve.TypeOwner::Interface(0),
  }
  let func : @resolve.Function = {
    name: "lookup",
    kind: Freestanding,
    params: [("id", U32)],
    result: Some(Id(0)),
  }
  let gen = make_import_gen([typedef], func)
  gen.generate_interface_import(0)
  let content = get_import_content(gen)
  // Option = 2 cases → u8 disc
  inspect(content.contains("cabi_read_u8(retptr"), content="true")
  // payload at offset 4 (aligned to s32 = 4)
  inspect(content.contains("retptr + 4"), content="true")
  // retptr size = 8
  inspect(content.contains("cabi_realloc(0, 0, 4, 8)"), content="true")
}

///|
/// Test import codegen: variant param lowering uses cabi_write_u8 for disc and correct offset
test "import_codegen_variant_param_lower" {
  let typedef : @resolve.TypeDef = {
    name: Some("value"),
    kind: Variant(
      [
        { name: "val-null", case_type: None },
        { name: "val-int", case_type: Some(S32) },
        { name: "val-float", case_type: Some(F64) },
      ],
    ),
    owner: @resolve.TypeOwner::Interface(0),
  }
  let func : @resolve.Function = {
    name: "set-value",
    kind: Freestanding,
    params: [("val", Id(0))],
    result: None,
  }
  let gen = make_import_gen([typedef], func)
  gen.generate_interface_import(0)
  let content = get_import_content(gen)
  // Disc write must use u8 (≤256 cases)
  inspect(content.contains("cabi_write_u8(p0_ptr"), content="true")
  // Must NOT use cabi_write_i32 for discriminant
  // (check that write_i32 is only used for payload, not for disc at ptr+0)
  inspect(content.contains("cabi_write_i32(p0_ptr,"), content="false")
  // Payload offset = align_to(1, 8) = 8 for f64 case
  inspect(content.contains("p0_ptr + 8"), content="true")
}

///|
/// Test import codegen: option param lowering uses cabi_write_u8 for disc
test "import_codegen_option_param_lower" {
  let typedef : @resolve.TypeDef = {
    name: Some("opt"),
    kind: Option(F64),
    owner: @resolve.TypeOwner::Interface(0),
  }
  let func : @resolve.Function = {
    name: "maybe-set",
    kind: Freestanding,
    params: [("val", Id(0))],
    result: None,
  }
  let gen = make_import_gen([typedef], func)
  gen.generate_interface_import(0)
  let content = get_import_content(gen)
  // Option disc write must use u8
  inspect(content.contains("cabi_write_u8(p0_ptr"), content="true")
  // Payload at offset 8 (f64 alignment)
  inspect(content.contains("p0_ptr + 8"), content="true")
  // Alloc size = 16
  inspect(content.contains("cabi_realloc(0, 0, 8, 16)"), content="true")
}

///|
/// Test import codegen: result param lowering uses correct disc and offset
test "import_codegen_result_param_lower" {
  let typedef : @resolve.TypeDef = {
    name: Some("res"),
    kind: Result(ok=Some(S32), err=Some(String_)),
    owner: @resolve.TypeOwner::Interface(0),
  }
  let func : @resolve.Function = {
    name: "send-result",
    kind: Freestanding,
    params: [("val", Id(0))],
    result: None,
  }
  let gen = make_import_gen([typedef], func)
  gen.generate_interface_import(0)
  let content = get_import_content(gen)
  // Result disc write must use u8 (2 cases)
  inspect(content.contains("cabi_write_u8(p0_ptr"), content="true")
  // payload at offset 4 (max align = 4 from s32 and string ptr)
  inspect(content.contains("p0_ptr + 4"), content="true")
}

///|
/// Test detect_dependencies with no external imports
test "detect_dependencies_no_external" {
  // Create a resolve with single package (no external deps)
  let iref : @resolve.InterfaceRef = { id: 0 }
  let world : @resolve.World = {
    name: "my-world",
    imports: { "types": @resolve.WorldItem::Interface(iref) },
    exports: {},
    pkg: Some(0), // same package
  }
  let iface : @resolve.Interface = {
    name: Some("types"),
    functions: {},
    types: {},
    pkg: Some(0), // same package
  }
  let pkg_name : @resolve.PackageName = { ns: "my", name: "app", version: None }
  let pkg : @resolve.Package = {
    name: pkg_name,
    interfaces: { "types": 0 },
    worlds: { "my-world": 0 },
  }
  let resolve : @resolve.Resolve = {
    worlds: [world],
    interfaces: [iface],
    types: [],
    packages: [pkg],
  }
  let opts = GeneratorOpts::default()
  let gen = Generator::new(resolve, 0, opts)
  let deps = gen.detect_dependencies(resolve.worlds[0])
  inspect(deps.length(), content="0")
}
