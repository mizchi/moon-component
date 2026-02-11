/// OCI registry fetch for WIT dependencies

///|
/// Convert @resolve.PackageName to @oci_types.PackageName
pub fn to_oci_pkg(pkg : @resolve.PackageName) -> @oci_types.PackageName? {
  @oci_types.PackageName::parse(pkg.ns + ":" + pkg.name)
}

///|
/// Default registry host for wa.dev
let default_registry_host : String = "wa.dev"

///|
/// Fetch a single WIT package from OCI registry and write to output directory.
pub async fn fetch_wit_package(
  pkg : @resolve.PackageName,
  output_dir : String,
  registry_host? : String,
) -> Unit raise Error {
  let host = match registry_host {
    Some(h) => h
    None => default_registry_host
  }
  let config = @discovery.fetch_registry_config(host)
  let (registry, prefix) = match config.preferred {
    Oci(oci) => (oci.registry, oci.namespace_prefix)
    _ => raise Failure::Failure("only OCI backend is supported")
  }
  guard to_oci_pkg(pkg) is Some(oci_pkg) else {
    raise Failure::Failure("invalid package name: " + pkg.to_string())
  }
  let version = match pkg.version {
    Some(v) => v
    None =>
      raise Failure::Failure(
        "version is required for fetch: " + pkg.to_string(),
      )
  }
  let client = @oci.OciClient::new(registry, prefix, oci_pkg)
  let wasm_bytes = client.pull_wasm(oci_pkg, version)

  // Write to output directory
  let dir = output_dir + "/" + pkg.ns + "_" + pkg.name
  mkdir_p(dir)
  let path = dir + "/" + pkg.ns + "_" + pkg.name + ".wasm"
  @fs.write_bytes_to_file(path, wasm_bytes) catch {
    e => raise Failure::Failure("failed to write: " + e.to_string())
  }
}

///|
/// Fetch multiple WIT dependencies from OCI registry.
pub async fn fetch_wit_deps(
  deps : Array[@resolve.PackageName],
  wit_dir : String,
  registry_host? : String,
) -> Unit raise Error {
  let host = match registry_host {
    Some(h) => h
    None => default_registry_host
  }
  let config = @discovery.fetch_registry_config(host)
  let (registry, prefix) = match config.preferred {
    Oci(oci) => (oci.registry, oci.namespace_prefix)
    _ => raise Failure::Failure("only OCI backend is supported")
  }
  let deps_dir = wit_dir + "/deps"
  mkdir_p(deps_dir)
  for dep in deps {
    guard to_oci_pkg(dep) is Some(oci_pkg) else {
      println("Warning: invalid package name: " + dep.to_string())
      continue
    }
    let version = match dep.version {
      Some(v) => v
      None => {
        println("Warning: skipping " + dep.to_string() + " (no version)")
        continue
      }
    }
    let client = @oci.OciClient::new(registry, prefix, oci_pkg)
    let wasm_bytes = client.pull_wasm(oci_pkg, version)
    let dir = deps_dir + "/" + dep.ns + "_" + dep.name
    mkdir_p(dir)
    let path = dir + "/" + dep.ns + "_" + dep.name + ".wasm"
    @fs.write_bytes_to_file(path, wasm_bytes) catch {
      e =>
        raise Failure::Failure(
          "failed to write " + path + ": " + e.to_string(),
        )
    }
    println("Fetched " + dep.to_string() + " -> " + path)
  }
}

///|
fn mkdir_p(dir : String) -> Unit {
  let parts : Array[String] = dir
    .split("/")
    .map(fn(sv) { sv.to_string() })
    .collect()
  let starts_with_slash = dir.length() > 0 && dir.to_array()[0] == '/'
  let mut current = ""
  for part in parts {
    if part.length() == 0 {
      continue
    }
    current = if current.length() == 0 {
      if starts_with_slash {
        "/" + part
      } else {
        part
      }
    } else {
      current + "/" + part
    }
    @fs.create_dir(current) catch {
      _ => ()
    }
  }
}
