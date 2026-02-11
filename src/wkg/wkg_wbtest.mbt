///|
/// Test PackageName parsing
test "package_name_parse" {
  let pkg = @resolve.PackageName::parse("wasi:http@0.2.0")
  inspect(
    pkg,
    content="Some({ns: \"wasi\", name: \"http\", version: Some(\"0.2.0\")})",
  )
  let pkg2 = @resolve.PackageName::parse("wasi:cli")
  inspect(pkg2, content="Some({ns: \"wasi\", name: \"cli\", version: None})")
  let pkg3 = @resolve.PackageName::parse("invalid")
  inspect(pkg3, content="None")
}

///|
/// Test PackageName to_string
test "package_name_to_string" {
  let pkg : @resolve.PackageName = {
    ns: "wasi",
    name: "http",
    version: Some("0.2.0"),
  }
  inspect(pkg.to_string(), content="wasi:http@0.2.0")
  let pkg2 : @resolve.PackageName = { ns: "wasi", name: "cli", version: None }
  inspect(pkg2.to_string(), content="wasi:cli")
}

///|
/// Test WkgRegistry URLs
test "wkg_registry_urls" {
  let registry = WkgRegistry::default()
  let pkg : @resolve.PackageName = {
    ns: "wasi",
    name: "http",
    version: Some("0.2.0"),
  }
  inspect(registry.package_url(pkg), content="https://wa.dev/wasi:http@0.2.0")
  inspect(
    registry.wit_url(pkg),
    content="https://wa.dev/v1/wasi/http/0.2.0/wit",
  )
  let pkg2 : @resolve.PackageName = { ns: "wasi", name: "cli", version: None }
  inspect(registry.wit_url(pkg2), content="https://wa.dev/v1/wasi/cli/wit")
}

///|
/// Test wkg_fetch_command
test "wkg_fetch_command" {
  let pkg : @resolve.PackageName = {
    ns: "wasi",
    name: "http",
    version: Some("0.2.0"),
  }
  inspect(
    wkg_fetch_command(pkg, "wit/deps"),
    content="wkg wit fetch wasi:http@0.2.0 -o wit/deps",
  )
}

///|
/// Test generate_fetch_script
test "generate_fetch_script" {
  let deps : Array[@resolve.PackageName] = [
    { ns: "wasi", name: "http", version: Some("0.2.0") },
    { ns: "wasi", name: "cli", version: None },
  ]
  let script = generate_fetch_script(deps, "wit")
  inspect(script.contains("wkg wit fetch wasi:http@0.2.0"), content="true")
  inspect(script.contains("wkg wit fetch wasi:cli"), content="true")
  inspect(script.contains("mkdir -p"), content="true")
}
