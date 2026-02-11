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
        file.content.contains("\"wasi:http\": \"https://wa.dev/wasi:http@0.2.0\""),
        content="true",
      )
      // Check build config present
      inspect(
        file.content.contains("\"build\": { \"kind\": \"component\", \"flags\": [\"-Oz\"] }"),
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
