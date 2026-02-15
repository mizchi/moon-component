///|
/// CLI entry point for moon-component
async fn main {
  let args = @sys.get_cli_args()
  if args.length() >= 2 && args[1] == "plug" {
    cmd_plug(args)
    return
  }
  if args.length() >= 2 && args[1] == "compose" {
    cmd_compose_wac(args)
    return
  }
  if args.length() >= 2 && args[1] == "wac-parse" {
    cmd_wac_parse(args)
    return
  }
  if args.length() >= 2 && args[1] == "wac-resolve" {
    cmd_wac_resolve(args)
    return
  }
  if args.length() >= 2 && args[1] == "targets" {
    cmd_targets(args)
    return
  }
  if args.length() >= 2 && args[1] == "fetch" {
    cmd_fetch(args)
    return
  }
  if args.length() >= 2 && args[1] == "componentize" {
    cmd_componentize(args)
    return
  }
  // Handle "generate" as alias for default command
  let generate_mode = args.length() >= 2 && args[1] == "generate"
  if not(generate_mode) && args.length() < 2 {
    println(
      "Usage: moon-component generate <wit-path> [options]\n       moon-component <resolve.json|wit-path> [options]\n       moon-component plug <socket.wasm> --plug <plug.wasm>... -o <out.wasm>\n       moon-component compose <composition.wac> -o <out.wasm>\n       moon-component wac-parse <composition.wac>\n       moon-component wac-resolve <composition.wac>\n       moon-component targets <component.wasm> <wit-path> [--world <name>]\n       moon-component fetch [options] <pkg-spec>...\n       moon-component componentize <core.wasm> --wit-dir <wit-dir> [--world <name>] -o <output.wasm>\n\nOptions:\n  --wit <path>          Treat input as WIT file or directory\n  --wit-dir <path>      Alias for --wit\n  --resolve-json <path> Treat input as resolve.json\n  --world <name>        World name when resolving WIT\n  --out-dir <dir>       Output directory\n  --project-name <name> Project name for imports\n  --gen-dir <dir>       Generated code directory (default: gen)\n  --impl-dir <dir>      Implementation directory (default: impl)\n  --no-impl             Don't generate impl files\n  --wkg                  Generate wkg.toml for wa.dev deployment\n  --wite                 Generate wite.config.jsonc for wite pipeline\n  --wkg-version <ver>   Package version (default: 0.1.0)\n  --pkg-format <fmt>    Package format: json (moon.pkg.json) or dsl (moon.pkg)\n  --js-string-builtins  Enable JS String Builtins (wasm-gc only)",
    )
    @sys.exit(1)
  }
  if generate_mode && args.length() < 3 {
    println("Usage: moon-component generate <wit-path> [options]")
    @sys.exit(1)
  }
  let mut input_path = if generate_mode { args[2] } else { args[1] }
  let mut input_kind = "auto"

  // Parse options
  let mut out_dir : String? = None
  let mut project_name : String? = None
  let mut gen_dir = "gen"
  let mut impl_dir = "impl"
  let mut generate_impl = true
  let mut generate_wkg = false
  let mut generate_wite = false
  let mut wkg_version = "0.1.0"
  let mut pkg_format : @codegen.PkgFormat = @codegen.Json
  let mut use_js_string_builtins = false
  let mut world_name : String? = None
  let mut i = if generate_mode { 3 } else { 2 }
  while i < args.length() {
    if (args[i] == "--wit" || args[i] == "--wit-dir") && i + 1 < args.length() {
      input_path = args[i + 1]
      input_kind = "wit"
      i = i + 2
    } else if args[i] == "--resolve-json" && i + 1 < args.length() {
      input_path = args[i + 1]
      input_kind = "json"
      i = i + 2
    } else if args[i] == "--world" && i + 1 < args.length() {
      world_name = Some(args[i + 1])
      i = i + 2
    } else if args[i] == "--out-dir" && i + 1 < args.length() {
      out_dir = Some(args[i + 1])
      i = i + 2
    } else if args[i] == "--project-name" && i + 1 < args.length() {
      project_name = Some(args[i + 1])
      i = i + 2
    } else if args[i] == "--gen-dir" && i + 1 < args.length() {
      gen_dir = args[i + 1]
      i = i + 2
    } else if args[i] == "--impl-dir" && i + 1 < args.length() {
      impl_dir = args[i + 1]
      i = i + 2
    } else if args[i] == "--no-impl" {
      generate_impl = false
      i = i + 1
    } else if args[i] == "--wkg" {
      generate_wkg = true
      i = i + 1
    } else if args[i] == "--wite" {
      generate_wite = true
      i = i + 1
    } else if args[i] == "--wkg-version" && i + 1 < args.length() {
      wkg_version = args[i + 1]
      i = i + 2
    } else if args[i] == "--pkg-format" && i + 1 < args.length() {
      pkg_format = if args[i + 1] == "dsl" {
        @codegen.Dsl
      } else {
        @codegen.Json
      }
      i = i + 2
    } else if args[i] == "--js-string-builtins" {
      use_js_string_builtins = true
      i = i + 1
    } else {
      i = i + 1
    }
  }
  let is_json = if input_kind == "json" {
    true
  } else if input_kind == "wit" {
    false
  } else {
    input_path.has_suffix(".json")
  }
  let input : @resolve.ResolveInput = if is_json {
    // Read and parse JSON
    let json_str = @fs.read_file_to_string(input_path) catch {
      _ => {
        println("Error reading file: " + input_path)
        abort("exit")
      }
    }
    let json = @json.parse(json_str) catch {
      _ => {
        println("Error parsing JSON")
        abort("exit")
      }
    }
    @json.from_json(json) catch {
      e => {
        println("Error decoding ResolveInput: " + e.to_string())
        abort("exit")
      }
    }
  } else {
    let resolved_result : Result[@wit.ResolveInput, @wit.ParseError] = match
      world_name {
      Some(name) => @wit.resolve_path(input_path, world=name)
      None => @wit.resolve_path(input_path)
    }
    let resolved = match resolved_result {
      Ok(v) => v
      Err(e) => {
        println("Error resolving WIT: " + e.to_string())
        abort("exit")
      }
    }
    let json = resolved.to_json()
    @json.from_json(json) catch {
      e => {
        println("Error decoding ResolveInput: " + e.to_string())
        abort("exit")
      }
    }
  }

  // Generate code
  let opts : @codegen.GeneratorOpts = {
    trait_exports: true,
    out_dir,
    project_name,
    gen_dir,
    impl_dir,
    generate_impl,
    generate_wkg,
    generate_wite,
    wkg_version,
    pkg_format,
    use_js_string_builtins,
  }
  let gen = @codegen.Generator::new(input.resolve, input.world_id, opts)
  let files = gen.generate()

  // Output files
  let mut gen_count = 0
  let mut stub_count = 0
  let mut skip_count = 0
  for file in files {
    // Check if we should write the file
    let should_write = if file.is_stub {
      // Skip stub if file already exists
      not(file_exists(file.path))
    } else {
      true
    }
    let display_path = display_path_for(file.path, out_dir)
    if should_write {
      if out_dir is Some(_) {
        // Write to file
        write_file(file.path, file.content)
        if file.is_stub {
          println("[STUB] " + display_path)
          stub_count = stub_count + 1
        } else {
          println(display_path)
          gen_count = gen_count + 1
        }
      } else {
        // Print to stdout
        if file.is_stub {
          println("=== [STUB] " + display_path + " ===")
          stub_count = stub_count + 1
        } else {
          println("=== " + display_path + " ===")
          gen_count = gen_count + 1
        }
        println(file.content)
      }
    } else {
      println("[SKIP] " + display_path + " (already exists)")
      skip_count = skip_count + 1
    }
  }
  let msg = "Generated " +
    gen_count.to_string() +
    " files, " +
    stub_count.to_string() +
    " stub files"
  if skip_count > 0 {
    println(msg + ", " + skip_count.to_string() + " skipped")
  } else {
    println(msg)
  }
}

///|
fn cmd_plug(args : Array[String]) -> Unit {
  if args.length() < 3 {
    plug_usage()
    @sys.exit(1)
  }
  let socket_path = args[2]
  let plugs : Array[String] = []
  let mut output_path : String? = None
  let mut socket_wit_path : String? = None
  let plug_wit_paths : Array[String] = []
  let mut best_effort = false
  let mut i = 3
  while i < args.length() {
    if args[i] == "--plug" && i + 1 < args.length() {
      plugs.push(args[i + 1])
      i = i + 2
    } else if args[i] == "--socket-wit" && i + 1 < args.length() {
      socket_wit_path = Some(args[i + 1])
      i = i + 2
    } else if args[i] == "--plug-wit" && i + 1 < args.length() {
      plug_wit_paths.push(args[i + 1])
      i = i + 2
    } else if (args[i] == "-o" || args[i] == "--output") &&
      i + 1 < args.length() {
      output_path = Some(args[i + 1])
      i = i + 2
    } else if args[i] == "--best-effort" {
      best_effort = true
      i = i + 1
    } else {
      i = i + 1
    }
  }
  if plugs.length() == 0 || output_path is None {
    plug_usage()
    @sys.exit(1)
  }
  if socket_wit_path is Some(_) || plug_wit_paths.length() > 0 {
    if socket_wit_path is None || plug_wit_paths.length() != plugs.length() {
      println(
        "Error: --socket-wit and --plug-wit must be specified together (one per plug).",
      )
      @sys.exit(1)
    }
  }
  let socket_bytes = @fs.read_file_to_bytes(socket_path) catch {
    e => {
      println("Error reading socket: " + e.to_string())
      abort("exit")
    }
  }
  let plug_bytes : Array[Bytes] = []
  for path in plugs {
    let bytes = @fs.read_file_to_bytes(path) catch {
      e => {
        println("Error reading plug: " + e.to_string())
        abort("exit")
      }
    }
    plug_bytes.push(bytes)
  }
  if socket_wit_path is Some(path) {
    let socket_res = match @wit.resolve_path(path) {
      Ok(v) => v
      Err(e) => {
        println("Error resolving socket WIT: " + e.to_string())
        @sys.exit(1)
        abort("exit")
      }
    }
    let plug_resolves : Array[@wit.ResolveInput] = []
    for wit_path in plug_wit_paths {
      let res = match @wit.resolve_path(wit_path) {
        Ok(v) => v
        Err(e) => {
          println("Error resolving plug WIT: " + e.to_string())
          @sys.exit(1)
          abort("exit")
        }
      }
      plug_resolves.push(res)
    }
    match @component.check_plug_wit(socket_res, plug_resolves) {
      Ok(_) => ()
      Err(msg) => {
        println("WIT check error: " + msg)
        @sys.exit(1)
      }
    }
  }
  let result = @component.plug_components(
    socket_bytes,
    plug_bytes,
    best_effort~,
  )
  match result {
    Ok(bytes) =>
      match output_path {
        Some(out) =>
          @fs.write_bytes_to_file(out, bytes) catch {
            e => {
              println("Error writing output: " + e.to_string())
              @sys.exit(1)
            }
          }
        None => ()
      }
    Err(e) => {
      println("Plug error: " + e.to_string())
      @sys.exit(1)
    }
  }
}

///|
fn cmd_compose_wac(args : Array[String]) -> Unit {
  if args.length() < 3 {
    println(
      "Usage: moon-component compose <composition.wac> -o <out.wasm> [--best-effort] [--dce]",
    )
    @sys.exit(1)
  }
  let input_path = args[2]
  let mut output_path = "composed.wasm"
  let mut best_effort = false
  let mut dce = false
  let mut i = 3
  while i < args.length() {
    if (args[i] == "-o" || args[i] == "--output") && i + 1 < args.length() {
      output_path = args[i + 1]
      i = i + 2
    } else if args[i] == "--best-effort" {
      best_effort = true
      i = i + 1
    } else if args[i] == "--dce" {
      dce = true
      i = i + 1
    } else {
      i = i + 1
    }
  }
  let result = @composer.compose_wac_file(input_path, best_effort~, dce~)
  match result {
    Ok(bytes) => {
      write_file_bytes(output_path, bytes)
      println("Composed component: " + output_path)
    }
    Err(e) => {
      println("Error: " + e)
      @sys.exit(1)
    }
  }
}

///|
fn cmd_wac_parse(args : Array[String]) -> Unit {
  if args.length() < 3 {
    println("Usage: moon-component wac-parse <composition.wac>")
    @sys.exit(1)
  }
  let input_path = args[2]
  let source = @fs.read_file_to_string(input_path) catch {
    _ => {
      println("Error reading file: " + input_path)
      @sys.exit(1)
      abort("exit")
    }
  }
  let parsed = @composer.parse_wac(source)
  match parsed {
    Ok(doc) => println(doc.to_json().stringify(indent=2))
    Err(e) => {
      println("Error: " + e.to_string())
      @sys.exit(1)
    }
  }
}

///|
fn cmd_wac_resolve(args : Array[String]) -> Unit {
  if args.length() < 3 {
    println(
      "Usage: moon-component wac-resolve <composition.wac> [--best-effort]",
    )
    @sys.exit(1)
  }
  let input_path = args[2]
  let mut best_effort = false
  let mut i = 3
  while i < args.length() {
    if args[i] == "--best-effort" {
      best_effort = true
      i = i + 1
    } else {
      i = i + 1
    }
  }
  let source = @fs.read_file_to_string(input_path) catch {
    _ => {
      println("Error reading file: " + input_path)
      @sys.exit(1)
      abort("exit")
    }
  }
  let base = dirname(input_path)
  let base_dir = if base.length() == 0 { "." } else { base }
  let resolved = @composer.resolve_wac_summary(source, base_dir, best_effort~)
  match resolved {
    Ok(summary) => println(summary.to_json().stringify(indent=2))
    Err(e) => {
      println("Error: " + e)
      @sys.exit(1)
    }
  }
}

///|
fn plug_usage() -> Unit {
  println(
    "Usage: moon-component plug <socket.wasm> --plug <plug.wasm>... -o <out.wasm> [--best-effort]\n       moon-component plug <socket.wasm> --plug <plug.wasm>... -o <out.wasm> --socket-wit <wit-dir> --plug-wit <wit-dir>... [--best-effort]",
  )
}

///|
fn cmd_targets(args : Array[String]) -> Unit {
  if args.length() < 4 {
    targets_usage()
    @sys.exit(1)
  }
  let component_path = args[2]
  let wit_path = args[3]
  let mut world_name : String? = None
  let mut i = 4
  while i < args.length() {
    if args[i] == "--world" && i + 1 < args.length() {
      world_name = Some(args[i + 1])
      i = i + 2
    } else {
      i = i + 1
    }
  }
  let component_bytes = @fs.read_file_to_bytes(component_path) catch {
    e => {
      println("Error reading component: " + e.to_string())
      @sys.exit(1)
      abort("exit")
    }
  }
  let resolved_result : Result[@wit.ResolveInput, @wit.ParseError] = match
    world_name {
    Some(name) => @wit.resolve_path(wit_path, world=name)
    None => @wit.resolve_path(wit_path)
  }
  let resolved = match resolved_result {
    Ok(v) => v
    Err(e) => {
      println("Error resolving WIT: " + e.to_string())
      @sys.exit(1)
      abort("exit")
    }
  }
  match @component.check_component_targets(component_bytes, resolved) {
    Ok(_) => println("OK")
    Err(e) => {
      println("Error: " + e)
      @sys.exit(1)
      abort("exit")
    }
  }
}

///|
fn targets_usage() -> Unit {
  println(
    "Usage: moon-component targets <component.wasm> <wit-path> [--world <name>]\nNote: validates names/kinds and function types; instance types are best-effort.",
  )
}

///|
fn display_path_for(path : String, out_dir : String?) -> String {
  let norm_path = normalize_path(path)
  match out_dir {
    Some(out) => {
      let norm_out = normalize_path(out)
      let prefix = if norm_out == "/" { "/" } else { norm_out + "/" }
      if norm_path.has_prefix(prefix) {
        let rel = strip_prefix(norm_path, norm_out)
        if rel.length() == 0 {
          "."
        } else {
          rel
        }
      } else if norm_path == norm_out {
        "."
      } else {
        norm_path
      }
    }
    None => norm_path
  }
}

///|
fn normalize_path(path : String) -> String {
  let parts : Array[String] = path
    .split("/")
    .map(fn(sv) { sv.to_string() })
    .collect()
  let chars : Array[Char] = path.to_array()
  let is_abs = path.length() > 0 && chars[0] == '/'
  let cleaned : Array[String] = []
  for part in parts {
    if part.length() == 0 {
      continue
    }
    if part == "." {
      continue
    }
    cleaned.push(part)
  }
  if cleaned.length() == 0 {
    if is_abs {
      "/"
    } else {
      "."
    }
  } else {
    let sb = StringBuilder::new()
    if is_abs {
      sb.write_string("/")
    }
    for i, part in cleaned {
      if i > 0 {
        sb.write_string("/")
      }
      sb.write_string(part)
    }
    sb.to_string()
  }
}

///|
fn strip_prefix(path : String, prefix : String) -> String {
  if prefix.length() == 0 {
    return path
  }
  if not(path.has_prefix(prefix)) {
    return path
  }
  let chars : Array[Char] = path.to_array()
  let mut i = prefix.length()
  if i < chars.length() && chars[i] == '/' {
    i = i + 1
  }
  let sb = StringBuilder::new()
  for j = i; j < chars.length(); j = j + 1 {
    sb.write_char(chars[j])
  }
  sb.to_string()
}

///|
fn file_exists(path : String) -> Bool {
  // Try to read file, if it fails, file doesn't exist
  try {
    let _ = @fs.read_file_to_string(path)
    true
  } catch {
    _ => false
  }
}

///|
fn write_file(path : String, content : String) -> Unit {
  // Ensure directory exists
  let dir = dirname(path)
  if dir.length() > 0 {
    mkdir_p(dir)
  }
  @fs.write_string_to_file(path, content) catch {
    e => {
      println("Error writing file: " + path + " - " + e.to_string())
      abort("exit")
    }
  }
}

///|
fn write_file_bytes(path : String, content : Bytes) -> Unit {
  let dir = dirname(path)
  if dir.length() > 0 {
    mkdir_p(dir)
  }
  @fs.write_bytes_to_file(path, content) catch {
    e => {
      println("Error writing file: " + path + " - " + e.to_string())
      abort("exit")
    }
  }
}

///|
fn dirname(path : String) -> String {
  let chars : Array[Char] = path.to_array()
  let mut last_slash = -1
  for i, c in chars {
    if c == '/' {
      last_slash = i
    }
  }
  if last_slash <= 0 {
    ""
  } else {
    let result = StringBuilder::new()
    for i = 0; i < last_slash; i = i + 1 {
      result.write_char(chars[i])
    }
    result.to_string()
  }
}

///|
fn mkdir_p(dir : String) -> Unit {
  // Split by / and create each directory
  let parts : Array[String] = dir
    .split("/")
    .map(fn(sv) { sv.to_string() })
    .collect()
  // Handle absolute paths (starting with /)
  let starts_with_slash = dir.length() > 0 && dir.to_array()[0] == '/'
  let mut current = if starts_with_slash { "" } else { "" }
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
      _ => () // Directory may already exist
    }
  }
}

///|
async fn cmd_fetch(args : Array[String]) -> Unit {
  let mut registry_host : String? = None
  let mut wit_dir = "wit"
  let mut from_wit : String? = None
  let pkg_specs : Array[String] = []
  let mut i = 2
  while i < args.length() {
    if args[i] == "--registry" && i + 1 < args.length() {
      registry_host = Some(args[i + 1])
      i = i + 2
    } else if args[i] == "--wit-dir" && i + 1 < args.length() {
      wit_dir = args[i + 1]
      i = i + 2
    } else if args[i] == "--from-wit" && i + 1 < args.length() {
      from_wit = Some(args[i + 1])
      i = i + 2
    } else if args[i].has_prefix("--") {
      println("Unknown option: " + args[i])
      fetch_usage()
      @sys.exit(1)
    } else {
      pkg_specs.push(args[i])
      i = i + 1
    }
  }
  if from_wit is Some(wit_path) {
    // Resolve WIT and fetch all dependencies
    let resolved_result : Result[@wit.ResolveInput, @wit.ParseError] = @wit.resolve_path(
      wit_path,
    )
    let resolved = match resolved_result {
      Ok(v) => v
      Err(e) => {
        println("Error resolving WIT: " + e.to_string())
        @sys.exit(1)
        abort("exit")
      }
    }
    let json = resolved.to_json()
    let input : @resolve.ResolveInput = @json.from_json(json) catch {
      e => {
        println("Error decoding ResolveInput: " + e.to_string())
        @sys.exit(1)
        abort("exit")
      }
    }
    let opts = @codegen.GeneratorOpts::default()
    let gen = @codegen.Generator::new(input.resolve, input.world_id, opts)
    let world = input.resolve.worlds[input.world_id]
    let deps = gen.detect_dependencies(world)
    if deps.length() == 0 {
      println("No external dependencies found.")
      return
    }
    println("Fetching " + deps.length().to_string() + " dependencies...")
    @fetch.fetch_wit_deps(deps, wit_dir, registry_host?) catch {
      e => {
        println("Error fetching dependencies: " + e.to_string())
        @sys.exit(1)
      }
    }
    println("Done.")
    return
  }
  if pkg_specs.length() == 0 {
    fetch_usage()
    @sys.exit(1)
  }
  // Fetch specified packages
  for spec in pkg_specs {
    guard @resolve.PackageName::parse(spec) is Some(pkg) else {
      println("Invalid package spec: " + spec)
      println("Expected format: namespace:name@version (e.g., wasi:http@0.2.0)")
      @sys.exit(1)
      continue
    }
    println("Fetching " + pkg.to_string() + "...")
    @fetch.fetch_wit_package(pkg, wit_dir + "/deps", registry_host?) catch {
      e => {
        println("Error fetching " + spec + ": " + e.to_string())
        @sys.exit(1)
      }
    }
  }
  println("Done.")
}

///|
fn fetch_usage() -> Unit {
  println(
    "Usage: moon-component fetch [options] <pkg-spec>...\n       moon-component fetch --from-wit <wit-path> [options]\n\nOptions:\n  --registry <host>   Registry host (default: wa.dev)\n  --wit-dir <dir>     WIT output directory (default: wit)\n  --from-wit <path>   Resolve WIT and fetch all dependencies\n\nExamples:\n  moon-component fetch wasi:http@0.2.0\n  moon-component fetch --from-wit wit/world.wit --wit-dir wit",
  )
}
