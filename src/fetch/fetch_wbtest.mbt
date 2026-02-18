///|
/// Test WkgRegistry URL generation used by fetch
test "wit_url_generation" {
  let registry = @wkg.WkgRegistry::default()
  let pkg : @resolve.PackageName = {
    ns: "wasi",
    name: "http",
    version: Some("0.2.0"),
  }
  let url = registry.wit_url(pkg)
  inspect(url, content="https://wa.dev/v1/wasi/http/0.2.0/wit")
}

///|
test "wit_url_no_version" {
  let registry = @wkg.WkgRegistry::default()
  let pkg : @resolve.PackageName = { ns: "wasi", name: "cli", version: None }
  let url = registry.wit_url(pkg)
  inspect(url, content="https://wa.dev/v1/wasi/cli/wit")
}
