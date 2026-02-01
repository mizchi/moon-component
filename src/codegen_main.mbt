/// MoonBit code generator for WIT - Core

///|
/// Package format for generated files
pub(all) enum PkgFormat {
  /// moon.pkg.json (JSON format)
  Json
  /// moon.pkg (MoonBit DSL format)
  Dsl
} derive(Show, Eq)

///|
/// Generator options
pub(all) struct GeneratorOpts {
  trait_exports : Bool
  out_dir : String?
  project_name : String?
  gen_dir : String
  impl_dir : String
  generate_impl : Bool
  generate_wkg : Bool
  wkg_version : String
  pkg_format : PkgFormat
  use_js_string_builtins : Bool
} derive(Show)

///|
pub fn GeneratorOpts::default() -> GeneratorOpts {
  {
    trait_exports: true,
    out_dir: None,
    project_name: None,
    gen_dir: "gen",
    impl_dir: "impl",
    generate_impl: true,
    generate_wkg: false,
    wkg_version: "0.1.0",
    pkg_format: Json,
    use_js_string_builtins: false,
  }
}

///|
/// Generated file
pub struct GeneratedFile {
  path : String
  content : String
  is_stub : Bool // stub files should not overwrite existing
} derive(Show)

///|
/// Export info for impl entry point generation
pub struct ExportInfo {
  func_name : String // e.g., "wasmExportGreet"
  wit_name : String // e.g., "local:hello/greet#greet"
  ffi_params : Array[String] // e.g., ["p0_ptr : Int", "p0_len : Int"]
  ffi_return_type : String // e.g., "Int", "Unit", "Float"
  returns_indirect : Bool // true if returns via retptr
} derive(Show)

///|
/// Code generator
pub struct Generator {
  opts : GeneratorOpts
  resolve : @resolve.Resolve
  world_id : Int
  output : Array[GeneratedFile]
  exports_info : Array[ExportInfo]
  moon_mod_name : Ref[String]
}

///|
pub fn Generator::new(
  resolve : @resolve.Resolve,
  world_id : Int,
  opts : GeneratorOpts,
) -> Generator {
  {
    opts,
    resolve,
    world_id,
    output: [],
    exports_info: [],
    moon_mod_name: { val: "" },
  }
}

///|
/// Generate all files
pub fn Generator::generate(self : Generator) -> Array[GeneratedFile] {
  let world = self.resolve.worlds[self.world_id]

  // Load or generate moon.mod.json first
  self.load_or_generate_moon_mod(world)

  // Generate canonical ABI helpers
  self.generate_cabi()

  // Generate exports
  for _, item in world.exports {
    match item {
      Interface(iref) => self.generate_interface_export(iref.id)
      Function(_) => () // TODO: world-level functions
    }
  }

  // Generate imports
  for _, item in world.imports {
    match item {
      Interface(iref) => self.generate_interface_import(iref.id)
      Function(_) => () // TODO
    }
  }

  // Generate wkg.toml if requested
  if self.opts.generate_wkg {
    self.generate_wkg_toml(world)
  }

  // Generate impl/moon.pkg.json
  self.generate_impl_pkg()
  self.output
}
