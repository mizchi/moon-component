///|
/// CLI entry point for moon-component
fn main {
  let args = @sys.get_cli_args()
  if args.length() < 2 {
    println(
      "Usage: moon-component <resolve.json> [options]\n\nOptions:\n  --out-dir <dir>       Output directory\n  --project-name <name> Project name for imports\n  --gen-dir <dir>       Generated code directory (default: gen)\n  --impl-dir <dir>      Implementation directory (default: impl)\n  --no-impl             Don't generate impl files\n  --wkg                  Generate wkg.toml for wa.dev deployment\n  --wkg-version <ver>   Package version (default: 0.1.0)\n  --pkg-format <fmt>    Package format: json (moon.pkg.json) or dsl (moon.pkg)\n  --js-string-builtins  Enable JS String Builtins (wasm-gc only)",
    )
    @sys.exit(1)
  }
  let json_path = args[1]

  // Parse options
  let mut out_dir : String? = None
  let mut project_name : String? = None
  let mut gen_dir = "gen"
  let mut impl_dir = "impl"
  let mut generate_impl = true
  let mut generate_wkg = false
  let mut wkg_version = "0.1.0"
  let mut pkg_format : @codegen.PkgFormat = @codegen.Json
  let mut use_js_string_builtins = false
  let mut i = 2
  while i < args.length() {
    if args[i] == "--out-dir" && i + 1 < args.length() {
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

  // Read and parse JSON
  let json_str = @fs.read_file_to_string(json_path) catch {
    _ => {
      println("Error reading file: " + json_path)
      abort("exit")
    }
  }
  let json = @json.parse(json_str) catch {
    _ => {
      println("Error parsing JSON")
      abort("exit")
    }
  }
  let input : @resolve.ResolveInput = @json.from_json(json) catch {
    e => {
      println("Error decoding ResolveInput: " + e.to_string())
      abort("exit")
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
    if should_write {
      if out_dir is Some(_) {
        // Write to file
        write_file(file.path, file.content)
        if file.is_stub {
          println("[STUB] " + file.path)
          stub_count = stub_count + 1
        } else {
          println(file.path)
          gen_count = gen_count + 1
        }
      } else {
        // Print to stdout
        if file.is_stub {
          println("=== [STUB] " + file.path + " ===")
          stub_count = stub_count + 1
        } else {
          println("=== " + file.path + " ===")
          gen_count = gen_count + 1
        }
        println(file.content)
      }
    } else {
      println("[SKIP] " + file.path + " (already exists)")
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
