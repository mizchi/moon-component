/// WIT package fetch via wa.dev HTTP API

///|
/// Fetch a single WIT package from wa.dev and write to output directory.
pub async fn fetch_wit_package(
  pkg : @resolve.PackageName,
  output_dir : String,
  registry_host? : String,
) -> Unit raise Error {
  let registry = match registry_host {
    Some(h) => @wkg.WkgRegistry::new("https://" + h)
    None => @wkg.WkgRegistry::default()
  }
  let url = registry.wit_url(pkg)
  let (resp, body) = @http.get(url) catch {
    @http.NetworkError(msg) =>
      raise Failure::Failure("HTTP error fetching " + url + ": " + msg)
    @http.InvalidUrl(msg) =>
      raise Failure::Failure("Invalid URL: " + msg)
    @http.TimeoutError => raise Failure::Failure("Timeout fetching " + url)
    @http.NotSupported =>
      raise Failure::Failure("HTTP not supported on this target")
  }
  if resp.code != 200 {
    raise Failure::Failure(
      "HTTP " + resp.code.to_string() + " fetching " + url,
    )
  }
  let wasm_bytes = body.binary()

  // Write to output directory
  let dir = output_dir + "/" + pkg.ns + "_" + pkg.name
  @fs.mkdir(dir, permission=0o755, recursive=true) catch { _ => () }
  let path = dir + "/" + pkg.ns + "_" + pkg.name + ".wasm"
  @fs.write_file(path, body) catch {
    @fs.IOError(msg) =>
      raise Failure::Failure("failed to write: " + msg)
  }
  ignore(wasm_bytes)
}

///|
/// Fetch multiple WIT dependencies from wa.dev.
pub async fn fetch_wit_deps(
  deps : Array[@resolve.PackageName],
  wit_dir : String,
  registry_host? : String,
) -> Unit raise Error {
  let registry = match registry_host {
    Some(h) => @wkg.WkgRegistry::new("https://" + h)
    None => @wkg.WkgRegistry::default()
  }
  let deps_dir = wit_dir + "/deps"
  @fs.mkdir(deps_dir, permission=0o755, recursive=true) catch { _ => () }
  for dep in deps {
    let version = match dep.version {
      Some(v) => v
      None => {
        println("Warning: skipping " + dep.to_string() + " (no version)")
        continue
      }
    }
    let url = registry.wit_url(dep)
    let (resp, body) = @http.get(url) catch {
      _ => {
        println("Warning: failed to fetch " + dep.to_string())
        continue
      }
    }
    if resp.code != 200 {
      println(
        "Warning: HTTP " +
        resp.code.to_string() +
        " fetching " +
        dep.to_string(),
      )
      continue
    }
    let dir = deps_dir + "/" + dep.ns + "_" + dep.name
    @fs.mkdir(dir, permission=0o755, recursive=true) catch { _ => () }
    let path = dir + "/" + dep.ns + "_" + dep.name + ".wasm"
    @fs.write_file(path, body) catch {
      @fs.IOError(msg) =>
        raise Failure::Failure("failed to write " + path + ": " + msg)
    }
    println("Fetched " + dep.to_string() + " -> " + path)
    ignore(version)
  }
}
