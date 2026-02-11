///|
/// Test to_oci_pkg conversion
test "to_oci_pkg" {
  let pkg : @resolve.PackageName = {
    ns: "wasi",
    name: "http",
    version: Some("0.2.0"),
  }
  guard to_oci_pkg(pkg) is Some(oci_pkg) else { fail("expected Some") }
  inspect(oci_pkg.to_string(), content="wasi:http")
}

///|
/// Test to_oci_pkg without version
test "to_oci_pkg_no_version" {
  let pkg : @resolve.PackageName = { ns: "wasi", name: "cli", version: None }
  guard to_oci_pkg(pkg) is Some(oci_pkg) else { fail("expected Some") }
  inspect(oci_pkg.to_string(), content="wasi:cli")
}
