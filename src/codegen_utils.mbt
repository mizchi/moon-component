/// Code generation utilities

///|
/// Convert string to PascalCase
fn to_pascal_case(s : String) -> String {
  let sb = StringBuilder::new()
  let mut cap = true
  for c in s {
    if c == '_' || c == '-' {
      cap = true
    } else if cap {
      sb.write_char(c.to_ascii_uppercase())
      cap = false
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// Convert string to camelCase (for FFI export names)
fn to_camel_case(s : String) -> String {
  let sb = StringBuilder::new()
  let mut capitalize_next = true
  for c in s {
    if c == '_' || c == '-' {
      capitalize_next = true
    } else if capitalize_next {
      sb.write_char(c.to_ascii_uppercase())
      capitalize_next = false
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// Convert string to snake_case
fn to_snake_case(s : String) -> String {
  let sb = StringBuilder::new()
  for c in s {
    if c == '-' {
      sb.write_char('_')
    } else if c.is_ascii_uppercase() {
      sb.write_char('_')
      sb.write_char(c.to_ascii_lowercase())
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// Normalize function name based on kind
fn normalize_func_name(name : String, kind : @resolve.FunctionKind) -> String {
  match kind {
    Freestanding => to_snake_case(name)
    Constructor(_) => {
      // name is "[constructor]type-name"
      let prefix = "[constructor]"
      if name.has_prefix(prefix) {
        to_snake_case(string_suffix(name, prefix.length())) + "_new"
      } else {
        to_snake_case(name)
      }
    }
    Method(_) => {
      // name is "[method]type-name.method-name"
      let prefix = "[method]"
      if name.has_prefix(prefix) {
        let rest = string_suffix(name, prefix.length())
        // Replace first '.' with '_' and convert to snake_case
        let sb = StringBuilder::new()
        let mut dot_found = false
        for c in rest {
          if c == '.' && not(dot_found) {
            sb.write_char('_')
            dot_found = true
          } else if c == '-' {
            sb.write_char('_')
          } else {
            sb.write_char(c)
          }
        }
        sb.to_string()
      } else {
        to_snake_case(name)
      }
    }
    Static(_) => {
      // name is "[static]type-name.func-name"
      let prefix = "[static]"
      if name.has_prefix(prefix) {
        let rest = string_suffix(name, prefix.length())
        let sb = StringBuilder::new()
        let mut dot_found = false
        for c in rest {
          if c == '.' && not(dot_found) {
            sb.write_char('_')
            dot_found = true
          } else if c == '-' {
            sb.write_char('_')
          } else {
            sb.write_char(c)
          }
        }
        sb.to_string()
      } else {
        to_snake_case(name)
      }
    }
  }
}

///|
/// Get substring from start index to end
fn string_suffix(s : String, start : Int) -> String {
  let sb = StringBuilder::new()
  let chars = s.to_array()
  for i = start; i < chars.length(); i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
/// Write export entries for JSON format from ExportInfo array (with leading comma)
fn write_exports_info_json(
  sb : StringBuilder,
  exports : Array[ExportInfo],
  indent : String,
) -> Unit {
  for info in exports {
    sb.write_string(",\n")
    sb.write_string(indent)
    sb.write_string("\"")
    sb.write_string(info.func_name)
    sb.write_string(":")
    sb.write_string(info.wit_name)
    sb.write_string("\"")
  }
}

///|
/// Write export entries for DSL format from ExportInfo array
fn write_exports_info_dsl(
  sb : StringBuilder,
  exports : Array[ExportInfo],
  indent : String,
) -> Unit {
  for info in exports {
    sb.write_string(indent)
    sb.write_string("\"")
    sb.write_string(info.func_name)
    sb.write_string(":")
    sb.write_string(info.wit_name)
    sb.write_string("\",\n")
  }
}

///|
fn Generator::impl_path(self : Generator, filename : String) -> String {
  match self.opts.out_dir {
    Some(out) => out + "/" + self.opts.impl_dir + "/" + filename
    None => self.opts.impl_dir + "/" + filename
  }
}

///|
fn Generator::cabi_import_path(self : Generator) -> String {
  match self.opts.project_name {
    Some(proj) => proj + "/" + self.opts.gen_dir + "/cabi"
    None => self.opts.gen_dir + "/cabi"
  }
}

///|
fn Generator::interface_path(
  self : Generator,
  id : Int,
  filename : String,
) -> String {
  let iface = self.resolve.interfaces[id]
  let pkg = iface.pkg.map(fn(pid) { self.resolve.packages[pid] })
  let unnamed = "unnamed"
  let iface_name = iface.name.unwrap_or(unnamed)
  let dir = match pkg {
    Some(p) => {
      let sb = StringBuilder::new()
      sb.write_string(self.opts.gen_dir)
      sb.write_string("/interface/")
      sb.write_string(p.name.ns)
      sb.write_string("/")
      sb.write_string(p.name.name)
      sb.write_string("/")
      sb.write_string(iface_name)
      sb.to_string()
    }
    None => {
      let sb = StringBuilder::new()
      sb.write_string(self.opts.gen_dir)
      sb.write_string("/interface/")
      sb.write_string(iface_name)
      sb.to_string()
    }
  }
  match self.opts.out_dir {
    Some(out) => out + "/" + dir + "/" + filename
    None => dir + "/" + filename
  }
}

///|
/// Dependency info for wkg.toml
pub struct WkgDependency {
  ns : String
  name : String
  version : String?
} derive(Show, Eq)

///|
/// Detect dependencies from world imports
fn Generator::detect_dependencies(
  self : Generator,
  world : @resolve.World,
) -> Array[WkgDependency] {
  let deps : Array[WkgDependency] = []
  let seen : Map[String, Bool] = {}

  // Get current package id
  let current_pkg_id = world.pkg

  // Scan imports for external interfaces
  for _, item in world.imports {
    match item {
      Interface(iref) => {
        let iface = self.resolve.interfaces[iref.id]
        match iface.pkg {
          Some(pkg_id) => {
            // Check if this is from a different package
            let is_external = match current_pkg_id {
              Some(curr_id) => pkg_id != curr_id
              None => true // No current package, treat all as external
            }
            if is_external {
              let pkg = self.resolve.packages[pkg_id]
              let key = pkg.name.ns + ":" + pkg.name.name
              if not(seen.contains(key)) {
                seen[key] = true
                deps.push({
                  ns: pkg.name.ns,
                  name: pkg.name.name,
                  version: pkg.name.version,
                })
              }
            }
          }
          None => ()
        }
      }
      Function(_) => ()
    }
  }
  deps
}

///|
/// Generate wkg.toml for wa.dev registry
fn Generator::generate_wkg_toml(
  self : Generator,
  world : @resolve.World,
) -> Unit {
  let sb = StringBuilder::new()
  sb.write_string("# wkg.toml - WebAssembly Package Registry config\n")
  sb.write_string("# Generated by wit-bindgen-moonbit\n\n")

  // Get package info from world
  let pkg_name = match world.pkg {
    Some(pkg_id) => {
      let pkg = self.resolve.packages[pkg_id]
      pkg.name.ns + ":" + pkg.name.name
    }
    None => {
      // Use world name as fallback
      let proj_name = match self.opts.project_name {
        Some(p) => p
        None => "my:component"
      }
      proj_name + "/" + world.name
    }
  }
  sb.write_string("[package]\n")
  sb.write_string("name = \"")
  sb.write_string(pkg_name)
  sb.write_string("\"\n")
  sb.write_string("version = \"")
  sb.write_string(self.opts.wkg_version)
  sb.write_string("\"\n\n")

  // Dependencies
  let deps = self.detect_dependencies(world)
  if deps.length() > 0 {
    sb.write_string("[dependencies]\n")
    for dep in deps {
      sb.write_string(dep.ns)
      sb.write_string(":")
      sb.write_string(dep.name)
      sb.write_string(" = { version = \"")
      match dep.version {
        Some(v) => sb.write_string(v)
        None => sb.write_string("*")
      }
      sb.write_string("\" }\n")
    }
    sb.write_string("\n")
  }
  sb.write_string("[component]\n")
  sb.write_string("wit = \"wit\"\n")
  let path = match self.opts.out_dir {
    Some(out) => out + "/wkg.toml"
    None => "wkg.toml"
  }
  self.output.push({ path, content: sb.to_string(), is_stub: false })
}

///|
/// Generate build.just for complex builds
fn Generator::generate_build_justfile(
  self : Generator,
  world : @resolve.World,
) -> Unit {
  let sb = StringBuilder::new()
  sb.write_string("# Justfile for building WebAssembly component\n")
  sb.write_string("# Generated by wit-bindgen-moonbit\n\n")
  sb.write_string("# Default target\n")
  sb.write_string("default:\n")
  sb.write_string("    just build\n\n")
  sb.write_string("# Build the component\n")
  sb.write_string("build:\n")
  sb.write_string("    moon build --target wasm\n")
  sb.write_string(
    "    wasm-tools component new target/wasm/release/build/main/main.wasm \\\n",
  )
  sb.write_string(
    "        --adapt wasi_snapshot_preview1=target/wasm/wasi_snapshot_preview1.wasm \\\n",
  )
  sb.write_string("        -o component.wasm\n\n")
  sb.write_string("# Build for release\n")
  sb.write_string("build-release:\n")
  sb.write_string("    moon build --target wasm --release\n")
  sb.write_string(
    "    wasm-tools component new target/wasm/release/build/main/main.wasm \\\n",
  )
  sb.write_string(
    "        --adapt wasi_snapshot_preview1=target/wasm/wasi_snapshot_preview1.wasm \\\n",
  )
  sb.write_string("        -o component.wasm\n\n")
  sb.write_string("# Generate bindings (rerun wit-bindgen)\n")
  sb.write_string("generate:\n")
  sb.write_string("    wit-bindgen moonbit wit/world.wit\n\n")
  sb.write_string("# Clean build artifacts\n")
  sb.write_string("clean:\n")
  sb.write_string("    moon clean\n")
  sb.write_string("    rm -f component.wasm\n\n")
  sb.write_string("# Test with wasmtime\n")
  sb.write_string("test-wasmtime:\n")
  sb.write_string("    wasmtime run component.wasm\n")
  let path = match self.opts.out_dir {
    Some(out) => out + "/build.just"
    None => "build.just"
  }
  self.output.push({ path, content: sb.to_string(), is_stub: false })
}

///|
/// Generate impl/impl.mbt (user implementation stub)
fn Generator::generate_impl(
  self : Generator,
  id : Int,
  iface_name : String,
  iface : @resolve.Interface,
) -> Unit {
  let sb = StringBuilder::new()
  sb.write_string("// User implementation for ")
  sb.write_string(iface_name)
  sb.write_string("\n")
  sb.write_string("// Edit this file to implement the interface\n\n")
  sb.write_string("///|\n")
  sb.write_string("struct Impl {}\n\n")
  sb.write_string("///|\n")
  sb.write_string("impl @exports.Exports for Impl with ")
  let mut first = true
  for _, func in iface.functions {
    if not(first) {
      sb.write_string("\n\n///|\n")
      sb.write_string("impl @exports.Exports for Impl with ")
    }
    first = false
    let normalized_name = normalize_func_name(func.name, func.kind)
    sb.write_string(normalized_name)
    sb.write_string("(")
    // Parameters
    let params_str = self.param_list(func.params)
    sb.write_string(params_str)
    sb.write_string(") -> ")
    sb.write_string(self.impl_result_type(func.result))
    sb.write_string(" {\n")
    sb.write_string("  // TODO: Implement ")
    sb.write_string(func.name)
    sb.write_string("\n")
    sb.write_string("  abort(\"not implemented\")\n")
    sb.write_string("}")
  }
  sb.write_string("\n\n///|\n")
  sb.write_string("fn main {\n  ()\n}")
  let path = self.impl_path("impl.mbt")
  self.output.push({ path, content: sb.to_string(), is_stub: true })
}

///|
/// Generate impl/moon.pkg.json (is-main with all exports)
fn Generator::generate_impl_pkg(self : Generator) -> Unit {
  if self.exports_info.length() == 0 {
    return
  }
  let sb = StringBuilder::new()
  let cabi_path = self.cabi_import_path()
  match self.opts.pkg_format {
    Json => {
      sb.write_string("{\n")
      sb.write_string("  \"is-main\": true,\n")
      sb.write_string("  \"import\": [\n")
      sb.write_string("    { \"path\": \"")
      sb.write_string(cabi_path)
      sb.write_string("\", \"alias\": \"cabi\" }\n")
      sb.write_string("  ],\n")
      sb.write_string("  \"link\": {\n")
      sb.write_string("    \"wasm\": {\n")
      sb.write_string("      \"exports\": [\n")
      sb.write_string("        \"cabi_realloc:cabi_realloc\"")
      write_exports_info_json(sb, self.exports_info, "        ")
      sb.write_string("\n      ],\n")
      sb.write_string("      \"export-memory-name\": \"memory\"\n")
      sb.write_string("    },\n")
      sb.write_string("    \"wasm-gc\": {\n")
      sb.write_string("      \"exports\": [\n")
      sb.write_string("        \"cabi_realloc:cabi_realloc\"")
      write_exports_info_json(sb, self.exports_info, "        ")
      sb.write_string("\n      ],\n")
      sb.write_string("      \"export-memory-name\": \"memory\"")
      if self.opts.use_js_string_builtins {
        sb.write_string(",\n      \"use-js-builtin-string\": true\n")
      } else {
        sb.write_string("\n")
      }
      sb.write_string("    }\n")
      sb.write_string("  }\n")
      sb.write_string("}\n")
    }
    Dsl => {
      sb.write_string("import(\n")
      sb.write_string("  \"")
      sb.write_string(cabi_path)
      sb.write_string("\" as cabi,\n")
      sb.write_string(")\n\n")
      sb.write_string("options(\n")
      sb.write_string("  is_main: true,\n")
      sb.write_string("  link: {\n")
      sb.write_string("    wasm: {\n")
      sb.write_string("      exports: [\n")
      sb.write_string("        \"cabi_realloc:cabi_realloc\",\n")
      write_exports_info_dsl(sb, self.exports_info, "        ")
      sb.write_string("      ],\n")
      sb.write_string("      export_memory_name: \"memory\",\n")
      sb.write_string("    },\n")
      sb.write_string("    wasm_gc: {\n")
      sb.write_string("      exports: [\n")
      sb.write_string("        \"cabi_realloc:cabi_realloc\",\n")
      write_exports_info_dsl(sb, self.exports_info, "        ")
      sb.write_string("      ],\n")
      sb.write_string("      export_memory_name: \"memory\",\n")
      if self.opts.use_js_string_builtins {
        sb.write_string("      use_js_builtin_string: true,\n")
      }
      sb.write_string("    },\n")
      sb.write_string("  },\n")
      sb.write_string(")\n")
    }
  }
  let filename = match self.opts.pkg_format {
    Json => "moon.pkg.json"
    Dsl => "moon.pkg"
  }
  let path = self.impl_path(filename)
  // is_stub: true so user's custom imports are preserved
  self.output.push({ path, content: sb.to_string(), is_stub: true })
}
