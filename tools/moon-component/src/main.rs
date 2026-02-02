use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use std::path::{Path, PathBuf};
use std::process::Command;
use wasm_encoder::Section;
use wit_parser::{Resolve, UnresolvedPackageGroup};

#[derive(Parser)]
#[command(name = "moon-component")]
#[command(about = "Generate MoonBit bindings for WebAssembly components")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Generate MoonBit bindings from WIT files (Guest/Host stubs)
    #[command(
        long_about = "Generate MoonBit bindings from WIT.\n\nOutputs:\n  gen/   generated bindings (regenerated)\n  impl/  implementation stubs (not overwritten)\n\nExamples:\n  moon-component generate wit/world.wit -o .\n  moon-component generate wit -o . --world my-world\n  moon-component generate wit/world.wit -o . --gen-dir gen --impl-dir impl\n  moon-component generate wit/world.wit -o . --no-impl\n\nAdvanced:\n  --pkg-format dsl   # emit moon.pkg instead of moon.pkg.json\n  --js-string-builtins  # enable JS string builtins (wasm-gc only)\n"
    )]
    Generate {
        /// WIT file or directory
        ///
        /// Example: wit/world.wit
        wit_path: PathBuf,

        /// Output directory
        ///
        /// Default: .
        #[arg(short, long, default_value = ".")]
        out_dir: PathBuf,

        /// Project name for imports (e.g., "my/project")
        #[arg(short, long)]
        project_name: Option<String>,

        /// Generated code directory (regenerated)
        #[arg(long, default_value = "gen")]
        gen_dir: String,

        /// Implementation directory
        ///
        /// Stubs are written here (not overwritten).
        #[arg(long, default_value = "impl")]
        impl_dir: String,

        /// Don't generate impl files
        #[arg(long)]
        no_impl: bool,

        /// Generate wkg.toml
        #[arg(long)]
        wkg: bool,

        /// Package version for wkg.toml
        #[arg(long, default_value = "0.1.0")]
        wkg_version: String,

        /// World to generate bindings for
        #[arg(short, long)]
        world: Option<String>,

        /// Package format: json (moon.pkg.json) or dsl (moon.pkg)
        #[arg(long, default_value = "json")]
        pkg_format: String,

        /// Enable JS String Builtins (wasm-gc only)
        #[arg(long)]
        js_string_builtins: bool,
    },

    /// Build the MoonBit project (core wasm / wasm-gc / native / js)
    #[command(
        long_about = "Build the MoonBit project.\n\nExamples:\n  moon-component build --target wasm --release\n  moon-component build --target wasm-gc --release\n  moon-component build --target native --release\n  moon-component build --target js --release\n"
    )]
    Build {
        /// Build target (wasm, wasm-gc, native, js)
        #[arg(short, long, default_value = "wasm")]
        target: String,

        /// Release build
        #[arg(long)]
        release: bool,
    },

    /// Create a WebAssembly component from a built core wasm module
    #[command(
        long_about = "Componentize a core wasm using a WIT directory.\n\nExample:\n  moon-component componentize _build/wasm/release/build/impl/impl.wasm \\\n    --wit-dir wit -o component.wasm\n"
    )]
    Componentize {
        /// Input wasm file
        wasm_file: PathBuf,

        /// WIT directory
        #[arg(short, long, default_value = "wit")]
        wit_dir: PathBuf,

        /// Output component file
        #[arg(short, long, default_value = "component.wasm")]
        output: PathBuf,
    },

    /// Full workflow: generate + build + componentize
    #[command(
        long_about = "One-shot workflow for WIT -> bindings -> build -> componentize.\n\nExamples:\n  moon-component component wit/world.wit -o out.wasm --release\n  moon-component component wit/world.wit -o out.wasm --world my-world --target wasm-gc\n"
    )]
    Component {
        /// WIT file or directory
        wit_path: PathBuf,

        /// Output component file
        #[arg(short, long, default_value = "component.wasm")]
        output: PathBuf,

        /// Project name for imports
        #[arg(short, long)]
        project_name: Option<String>,

        /// Build target
        #[arg(long, default_value = "wasm")]
        target: String,

        /// Release build
        #[arg(long)]
        release: bool,

        /// World to generate bindings for
        #[arg(short, long)]
        world: Option<String>,
    },

    /// Output WIT resolve as JSON (for debugging)
    #[command(
        long_about = "Resolve WIT and print the JSON graph.\n\nExamples:\n  moon-component resolve-json wit/world.wit\n  moon-component resolve-json wit --world my-world\n"
    )]
    ResolveJson {
        /// WIT file or directory
        wit_path: PathBuf,

        /// World to select
        #[arg(short, long)]
        world: Option<String>,
    },

    /// Initialize a new MoonBit component project
    #[command(
        long_about = "Create a new component project scaffold.\n\nExamples:\n  moon-component new my-component\n  moon-component new my-component --wit path/to/template.wit\n"
    )]
    New {
        /// Project name
        name: String,

        /// WIT file to use as template
        #[arg(short, long)]
        wit: Option<PathBuf>,
    },

    /// Initialize component directory in existing MoonBit project
    #[command(
        long_about = "Generate bindings and stub impl in an existing project.\n\nExamples:\n  moon-component init --wit wit\n  moon-component init --wit wit --component-dir component\n"
    )]
    Init {
        /// WIT file or directory
        #[arg(short, long, default_value = "wit")]
        wit: PathBuf,

        /// Component directory name
        #[arg(short, long, default_value = "component")]
        component_dir: String,

        /// World to generate bindings for
        #[arg(long)]
        world: Option<String>,
    },

    /// Fetch WIT dependencies using wkg
    #[command(
        long_about = "Fetch WIT dependencies and update lock files.\n\nExamples:\n  moon-component fetch --wit-dir wit\n  moon-component fetch --wit-dir wit --update\n"
    )]
    Fetch {
        /// WIT directory
        #[arg(short, long, default_value = "wit")]
        wit_dir: PathBuf,

        /// Output type: "wit" or "wasm"
        #[arg(short, long, default_value = "wit")]
        output_type: String,

        /// Update lock file (fetch latest versions)
        #[arg(long)]
        update: bool,
    },

    /// Generate WIT from MoonBit exports
    #[command(
        long_about = "Generate WIT from a MoonBit package (exports).\n\nExamples:\n  moon-component wit-from-moonbit . -o wit/world.wit -n mypkg\n  moon-component wit-from-moonbit . -o wit/world.wit -n mypkg --world my-world\n  moon-component wit-from-moonbit . -o wit/world.wit --interface exports\n  moon-component wit-from-moonbit . --check\n"
    )]
    WitFromMoonbit {
        /// MoonBit package directory (containing moon.pkg.json)
        #[arg(default_value = ".")]
        pkg_dir: PathBuf,

        /// Output WIT file
        #[arg(short, long, default_value = "world.wit")]
        output: PathBuf,

        /// Package namespace (e.g., "local")
        #[arg(short, long, default_value = "local")]
        namespace: String,

        /// Package name
        #[arg(short = 'n', long)]
        name: Option<String>,

        /// World name
        #[arg(short, long)]
        world: Option<String>,

        /// Interface name
        #[arg(short, long, default_value = "exports")]
        interface: String,

        /// Check only (don't generate WIT)
        #[arg(long)]
        check: bool,
    },

    /// Plug component exports into another component's imports
    #[command(hide = true)]
    Plug {
        /// Socket component (the one with imports)
        socket: PathBuf,

        /// Plug components (the ones providing exports)
        #[arg(required = true)]
        plugs: Vec<PathBuf>,

        /// Output component file
        #[arg(short, long, default_value = "composed.wasm")]
        output: PathBuf,
    },

    /// Compose components using a config or compose file
    #[command(
        long_about = "Preferred entry: compose via config.\n\nConfig example (moon-component.toml):\n  [bundle]\n  name = \"my/app\"\n  output = \"dist/app.wasm\"\n  entry = \"apps/main/component\"\n\n  [dependencies]\n  \"example:math\" = { path = \"libs/math/component\" }\n  \"local:regex/regex\" = { component = \"path/to/regex_guest.wasm\" }\n\n  [build]\n  target = \"wasm\"\n  release = true\n\nExamples:\n  moon-component compose -c moon-component.toml\n  moon-component compose -c moon-component.toml --build-only\n  moon-component compose -c moon-component.toml --dry-run\n  moon-component compose composition.wac -o composed.wasm\n"
    )]
    Compose {
        /// WAC source file
        wac_file: Option<PathBuf>,

        /// Compose from moon-component.toml (bundle config)
        #[arg(short, long)]
        config: Option<PathBuf>,

        /// Output component file
        #[arg(short, long, default_value = "composed.wasm")]
        output: PathBuf,

        /// Only build, don't compose (config mode only)
        #[arg(long)]
        build_only: bool,

        /// Show generated WAC without executing (config mode only)
        #[arg(long)]
        dry_run: bool,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Generate {
            wit_path,
            out_dir,
            project_name,
            gen_dir,
            impl_dir,
            no_impl,
            wkg,
            wkg_version,
            world,
            pkg_format,
            js_string_builtins,
        } => cmd_generate(
            &wit_path,
            &out_dir,
            project_name.as_deref(),
            &gen_dir,
            &impl_dir,
            !no_impl,
            wkg,
            &wkg_version,
            world.as_deref(),
            &pkg_format,
            js_string_builtins,
        ),

        Commands::Build { target, release } => cmd_build(&target, release),

        Commands::Componentize {
            wasm_file,
            wit_dir,
            output,
        } => cmd_componentize(&wasm_file, &wit_dir, &output),

        Commands::Component {
            wit_path,
            output,
            project_name,
            target,
            release,
            world,
        } => cmd_component(
            &wit_path,
            &output,
            project_name.as_deref(),
            &target,
            release,
            world.as_deref(),
        ),

        Commands::ResolveJson { wit_path, world } => cmd_resolve_json(&wit_path, world.as_deref()),

        Commands::New { name, wit } => cmd_new(&name, wit.as_deref()),

        Commands::Init {
            wit,
            component_dir,
            world,
        } => cmd_init(&wit, &component_dir, world.as_deref()),

        Commands::Fetch {
            wit_dir,
            output_type,
            update,
        } => cmd_fetch(&wit_dir, &output_type, update),

        Commands::WitFromMoonbit {
            pkg_dir,
            output,
            namespace,
            name,
            world,
            interface,
            check,
        } => cmd_wit_from_moonbit(
            &pkg_dir,
            &output,
            &namespace,
            name.as_deref(),
            world.as_deref(),
            &interface,
            check,
        ),

        Commands::Plug {
            socket,
            plugs,
            output,
        } => cmd_plug(&socket, &plugs, &output),

        Commands::Compose {
            wac_file,
            config,
            output,
            build_only,
            dry_run,
        } => {
            if let Some(cfg) = config {
                if wac_file.is_some() {
                    bail!("compose: use either <wac_file> or --config, not both");
                }
                cmd_bundle(&cfg, build_only, dry_run)
            } else if let Some(wac) = wac_file {
                if build_only || dry_run {
                    bail!("compose: --build-only/--dry-run require --config");
                }
                cmd_compose(&wac, &output)
            } else {
                bail!("compose: missing <wac_file> or --config");
            }
        }
    }
}

fn parse_wit(wit_path: &Path, world: Option<&str>) -> Result<(Resolve, wit_parser::WorldId)> {
    let mut resolve = Resolve::default();
    apply_wit_features(&mut resolve);

    // Determine wit directory
    let wit_dir = if wit_path.is_dir() {
        wit_path.to_path_buf()
    } else {
        wit_path.parent().unwrap_or(Path::new(".")).to_path_buf()
    };

    // Load deps first (if exists)
    let deps_dir = wit_dir.join("deps");
    if deps_dir.exists() && deps_dir.is_dir() {
        for entry in std::fs::read_dir(&deps_dir)? {
            let entry = entry?;
            let dep_path = entry.path();
            if dep_path.is_dir() {
                // Each subdirectory in deps/ is a package
                let pkg = UnresolvedPackageGroup::parse_dir(&dep_path)
                    .with_context(|| format!("failed to parse dep: {}", dep_path.display()))?;
                resolve.push_group(pkg)?;
            }
        }
    }

    // Then load the main package
    let pkg_id = if wit_path.is_dir() {
        let pkg = UnresolvedPackageGroup::parse_dir(wit_path)
            .with_context(|| format!("failed to parse WIT directory: {}", wit_path.display()))?;
        resolve.push_group(pkg)?
    } else {
        let pkg = UnresolvedPackageGroup::parse_file(wit_path)
            .with_context(|| format!("failed to parse WIT file: {}", wit_path.display()))?;
        resolve.push_group(pkg)?
    };

    // Find world
    let world_id = if let Some(world_name) = world {
        resolve.packages[pkg_id]
            .worlds
            .iter()
            .find(|(name, _)| *name == world_name)
            .map(|(_, id)| *id)
            .with_context(|| format!("world '{}' not found", world_name))?
    } else {
        // Use first world
        resolve.packages[pkg_id]
            .worlds
            .values()
            .next()
            .copied()
            .context("no world found in WIT")?
    };

    Ok((resolve, world_id))
}

fn apply_wit_features(resolve: &mut Resolve) {
    if let Ok(features) = std::env::var("MOON_COMPONENT_WIT_FEATURES") {
        for feature in features.split(|c| c == ',' || c == ' ' || c == '\t') {
            let feature = feature.trim();
            if !feature.is_empty() {
                resolve.features.insert(feature.to_string());
            }
        }
    }
}

fn cmd_generate(
    wit_path: &Path,
    out_dir: &Path,
    project_name: Option<&str>,
    gen_dir: &str,
    impl_dir: &str,
    generate_impl: bool,
    wkg: bool,
    wkg_version: &str,
    world: Option<&str>,
    pkg_format: &str,
    js_string_builtins: bool,
) -> Result<()> {
    eprintln!("Parsing WIT: {}", wit_path.display());
    let (resolve, world_id) = parse_wit(wit_path, world)?;

    // Generate JSON
    let json_output = serde_json::json!({
        "resolve": resolve,
        "world_id": world_id.index()
    });

    // Create temp file for JSON
    let temp_dir = std::env::temp_dir();
    let json_path = temp_dir.join("wit-resolve.json");
    std::fs::write(&json_path, serde_json::to_string_pretty(&json_output)?)?;

    // Convert out_dir to absolute path (relative to current dir, not codegen root)
    let abs_out_dir = if out_dir.is_absolute() {
        out_dir.to_path_buf()
    } else {
        std::env::current_dir()?.join(out_dir)
    };

    // Build moon codegen args
    let mut args = vec![
        "run".to_string(),
        "src/main".to_string(),
        "--".to_string(),
        json_path.to_string_lossy().to_string(),
        "--out-dir".to_string(),
        abs_out_dir.to_string_lossy().to_string(),
    ];

    if let Some(proj) = project_name {
        args.push("--project-name".to_string());
        args.push(proj.to_string());
    }

    args.push("--gen-dir".to_string());
    args.push(gen_dir.to_string());

    args.push("--impl-dir".to_string());
    args.push(impl_dir.to_string());

    if !generate_impl {
        args.push("--no-impl".to_string());
    }

    if wkg {
        args.push("--wkg".to_string());
        args.push("--wkg-version".to_string());
        args.push(wkg_version.to_string());
    }

    // Add pkg-format option
    args.push("--pkg-format".to_string());
    args.push(pkg_format.to_string());

    // Add js-string-builtins option
    if js_string_builtins {
        args.push("--js-string-builtins".to_string());
    }

    // Find the moon-component codegen root
    let codegen_root = find_codegen_root()?;

    eprintln!("Generating bindings...");
    let status = Command::new("moon")
        .args(&args)
        .current_dir(&codegen_root)
        .status()
        .context("failed to run moon")?;

    if !status.success() {
        bail!("moon run failed");
    }

    // Cleanup
    let _ = std::fs::remove_file(&json_path);

    eprintln!("Done!");
    Ok(())
}

fn cmd_build(target: &str, release: bool) -> Result<()> {
    eprintln!("Building MoonBit project...");

    let mut args = vec![
        "build".to_string(),
        "--target".to_string(),
        target.to_string(),
    ];

    if release {
        args.push("--release".to_string());
    }

    let status = Command::new("moon")
        .args(&args)
        .status()
        .context("failed to run moon build")?;

    if !status.success() {
        bail!("moon build failed");
    }

    eprintln!("Build complete!");
    Ok(())
}

fn cmd_componentize(wasm_file: &Path, wit_dir: &Path, output: &Path) -> Result<()> {
    eprintln!("Creating component from: {}", wasm_file.display());

    // Read input wasm
    let wasm_bytes = std::fs::read(wasm_file)
        .with_context(|| format!("failed to read wasm file: {}", wasm_file.display()))?;

    // Parse WIT with deps first (needed for ABI fix)
    let mut resolve = Resolve::default();

    // First, load deps if they exist
    let deps_dir = wit_dir.join("deps");
    if deps_dir.is_dir() {
        for entry in std::fs::read_dir(&deps_dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                let pkg = UnresolvedPackageGroup::parse_dir(&path)?;
                resolve.push_group(pkg)?;
            }
        }
    }

    // Then load the main package
    let pkg_id = if wit_dir.is_dir() {
        let pkg = UnresolvedPackageGroup::parse_dir(wit_dir)?;
        resolve.push_group(pkg)?
    } else {
        let pkg = UnresolvedPackageGroup::parse_file(wit_dir)?;
        resolve.push_group(pkg)?
    };

    // Find world
    let world_id = resolve.packages[pkg_id]
        .worlds
        .values()
        .next()
        .copied()
        .context("no world found in WIT")?;

    // Collect import function signatures that use retptr (should have no result)
    let retptr_imports = collect_retptr_imports(&resolve, world_id);

    // Fix MoonBit FFI ABI mismatch for imports
    let wasm_bytes = fix_import_abi(&wasm_bytes, &retptr_imports)?;

    // Embed WIT
    eprintln!("Embedding WIT metadata...");
    let encoded = wit_component::metadata::encode(
        &resolve,
        world_id,
        wit_component::StringEncoding::UTF8,
        None,
    )?;

    let section = wasm_encoder::CustomSection {
        name: std::borrow::Cow::Borrowed("component-type"),
        data: std::borrow::Cow::Borrowed(&encoded),
    };

    let mut module = wasm_bytes.clone();
    section.append_to(&mut module);

    // Create component
    eprintln!("Creating component...");
    let component = wit_component::ComponentEncoder::default()
        .module(&module)?
        .encode()?;

    // Write output
    std::fs::write(output, &component)
        .with_context(|| format!("failed to write component: {}", output.display()))?;

    eprintln!("Component created: {}", output.display());
    Ok(())
}

/// Check if a WIT type uses retptr for returns (complex types like string, list, etc.)
fn uses_retptr(resolve: &Resolve, ty: &wit_parser::Type) -> bool {
    match ty {
        wit_parser::Type::String => true,
        wit_parser::Type::Id(id) => {
            let type_def = &resolve.types[*id];
            match &type_def.kind {
                wit_parser::TypeDefKind::List(_) => true,
                wit_parser::TypeDefKind::Record(_) => true,
                wit_parser::TypeDefKind::Tuple(_) => true,
                wit_parser::TypeDefKind::Variant(_) => true,
                wit_parser::TypeDefKind::Option(_) => true,
                wit_parser::TypeDefKind::Result(_) => true,
                wit_parser::TypeDefKind::Type(inner) => uses_retptr(resolve, inner),
                _ => false,
            }
        }
        _ => false,
    }
}

/// Collect import function names that use retptr (and should have no result in canonical ABI)
fn collect_retptr_imports(
    resolve: &Resolve,
    world_id: wit_parser::WorldId,
) -> std::collections::HashSet<String> {
    let mut retptr_imports = std::collections::HashSet::new();
    let world = &resolve.worlds[world_id];

    for (name, item) in &world.imports {
        if let wit_parser::WorldItem::Interface { id, .. } = item {
            let interface = &resolve.interfaces[*id];
            let interface_name = match name {
                wit_parser::WorldKey::Name(n) => n.clone(),
                wit_parser::WorldKey::Interface(id) => {
                    let iface = &resolve.interfaces[*id];
                    if let Some(pkg_id) = iface.package {
                        let pkg = &resolve.packages[pkg_id];
                        format!(
                            "{}:{}/{}",
                            pkg.name.namespace,
                            pkg.name.name,
                            iface.name.as_ref().unwrap_or(&String::new())
                        )
                    } else {
                        iface.name.clone().unwrap_or_default()
                    }
                }
            };

            for (func_name, func) in &interface.functions {
                // Check if function returns a complex type (uses retptr) or returns void
                let needs_retptr = match &func.result {
                    Some(ty) => uses_retptr(resolve, ty),
                    None => false,
                };

                // Functions returning void also need ABI fix (MoonBit still returns i32)
                let returns_void = func.result.is_none();

                if needs_retptr || returns_void {
                    // Format: "interface_name" "func_name"
                    let import_key = format!("{}\t{}", interface_name, func_name);
                    retptr_imports.insert(import_key);
                }
            }
        }
    }

    retptr_imports
}

/// Fix MoonBit FFI ABI mismatch for imports
/// MoonBit generates `(result i32)` for imports, but Canonical ABI expects no result
/// when using retptr (for string/list returns) or for void-returning functions.
/// This function:
/// 1. Converts wasm to wat
/// 2. Identifies imports that should have no result (based on retptr_imports)
/// 3. Strips `(result i32)` from matching import types
/// 4. Removes `drop` instructions after calls to those imports
/// 5. Converts back to wasm
fn fix_import_abi(
    wasm_bytes: &[u8],
    retptr_imports: &std::collections::HashSet<String>,
) -> Result<Vec<u8>> {
    // Convert to WAT
    let wat_string = wasmprinter::print_bytes(wasm_bytes)?;

    // Check if there are imports that need fixing
    if !wat_string.contains("(import ") {
        return Ok(wasm_bytes.to_vec());
    }

    // Step 1: Collect imports that need fixing and their function indices
    // Format of import line: (import "module" "name" (func (;N;) (type M)))
    let mut imports_to_fix: std::collections::HashMap<usize, usize> =
        std::collections::HashMap::new(); // func_idx -> type_idx
    let mut func_indices_to_fix: Vec<usize> = Vec::new();

    for line in wat_string.lines() {
        if line.contains("(import ") && line.contains("(func (;") {
            // Extract module and name from import
            // Pattern: (import "module" "name" ...)
            let import_parts: Vec<&str> = line.split('"').collect();
            if import_parts.len() >= 4 {
                let module = import_parts[1];
                let name = import_parts[3];
                let import_key = format!("{}\t{}", module, name);

                // Check if this import should have no result (uses retptr or returns void)
                if retptr_imports.contains(&import_key) {
                    // Extract function index
                    if let Some(start) = line.find("(func (;") {
                        if let Some(end) = line[start + 8..].find(";)") {
                            if let Ok(func_idx) = line[start + 8..start + 8 + end].parse::<usize>()
                            {
                                // Extract type index
                                if let Some(type_start) = line.find("(type ") {
                                    if let Some(type_end) = line[type_start + 6..].find(')') {
                                        if let Ok(type_idx) = line
                                            [type_start + 6..type_start + 6 + type_end]
                                            .parse::<usize>()
                                        {
                                            imports_to_fix.insert(func_idx, type_idx);
                                            func_indices_to_fix.push(func_idx);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if imports_to_fix.is_empty() {
        return Ok(wasm_bytes.to_vec());
    }

    // Step 2: Build mapping of type indices -> equivalent without result
    let mut type_definitions: std::collections::HashMap<usize, String> =
        std::collections::HashMap::new();
    let mut type_without_result: std::collections::HashMap<usize, usize> =
        std::collections::HashMap::new();
    let mut param_to_noresult_type: std::collections::HashMap<String, usize> =
        std::collections::HashMap::new();

    // Collect types that need fixing
    let types_to_fix: std::collections::HashSet<usize> = imports_to_fix.values().copied().collect();

    // First pass: collect all type definitions
    for line in wat_string.lines() {
        if line.contains("(type (;") && line.contains("(func") {
            if let Some(start) = line.find("(type (;") {
                if let Some(end) = line[start + 8..].find(";)") {
                    if let Ok(type_idx) = line[start + 8..start + 8 + end].parse::<usize>() {
                        type_definitions.insert(type_idx, line.to_string());

                        // If this is a no-result type, record its param signature
                        if !line.contains("(result") {
                            if let Some(func_start) = line.find("(func") {
                                let params_part = &line[func_start..];
                                let params_only = if let Some(end_paren) = params_part.rfind("))") {
                                    params_part[..end_paren].to_string()
                                } else {
                                    params_part.to_string()
                                };
                                param_to_noresult_type.insert(params_only, type_idx);
                            }
                        }
                    }
                }
            }
        }
    }

    // Second pass: for each type to fix, find or create equivalent without result
    let mut next_type_idx = type_definitions.keys().max().copied().unwrap_or(0) + 1;
    let mut new_types: Vec<String> = Vec::new();

    for &type_idx in &types_to_fix {
        if let Some(type_def) = type_definitions.get(&type_idx) {
            if type_def.contains("(result i32)") {
                let no_result_def = type_def
                    .replace(" (result i32)", "")
                    .replace("(result i32)", "");
                if let Some(func_start) = no_result_def.find("(func") {
                    let params_part = &no_result_def[func_start..];
                    let params_only = if let Some(end_paren) = params_part.rfind("))") {
                        params_part[..end_paren].to_string()
                    } else {
                        params_part.to_string()
                    };

                    if let Some(&noresult_idx) = param_to_noresult_type.get(&params_only) {
                        type_without_result.insert(type_idx, noresult_idx);
                    } else {
                        // Create a new type without result
                        // params_only is like "(func (param i32 i32 i32)", need to add closing parens
                        let new_type_def =
                            format!("  (type (;{};) {}))", next_type_idx, params_only);
                        new_types.push(new_type_def);
                        type_without_result.insert(type_idx, next_type_idx);
                        param_to_noresult_type.insert(params_only, next_type_idx);
                        next_type_idx += 1;
                    }
                }
            }
        }
    }

    if type_without_result.is_empty() {
        return Ok(wasm_bytes.to_vec());
    }

    eprintln!(
        "Fixing import ABI for {} function(s), adding {} new type(s)...",
        imports_to_fix.len(),
        new_types.len()
    );

    // Step 3: Insert new types and replace type references for imports that need fixing
    let mut result_lines: Vec<String> = Vec::new();
    let mut inserted_new_types = false;

    for line in wat_string.lines() {
        let mut fixed_line = line.to_string();

        // Insert new types before the first import (after all type definitions)
        if !inserted_new_types && line.contains("(import ") && !new_types.is_empty() {
            for new_type in &new_types {
                result_lines.push(new_type.clone());
            }
            inserted_new_types = true;
        }

        if line.contains("(import ") {
            // Check if this import needs fixing
            let import_parts: Vec<&str> = line.split('"').collect();
            if import_parts.len() >= 4 {
                let module = import_parts[1];
                let name = import_parts[3];
                let import_key = format!("{}\t{}", module, name);

                if retptr_imports.contains(&import_key) {
                    for (&old_type, &new_type) in &type_without_result {
                        let old_ref = format!("(type {})", old_type);
                        let new_ref = format!("(type {})", new_type);
                        if fixed_line.contains(&old_ref) {
                            fixed_line = fixed_line.replace(&old_ref, &new_ref);
                        }
                    }
                }
            }
        }
        result_lines.push(fixed_line);
    }
    let mut fixed_wat = result_lines.join("\n");

    // Step 4: Remove drop after calls to import functions that were fixed
    let mut final_lines: Vec<String> = Vec::new();
    let lines: Vec<&str> = fixed_wat.lines().collect();
    let mut skip_next = false;
    for (i, line) in lines.iter().enumerate() {
        if skip_next {
            skip_next = false;
            continue;
        }
        // Check if this is a call to an import function that was fixed
        if line.trim().starts_with("call ") {
            let call_parts: Vec<&str> = line.trim().split_whitespace().collect();
            if call_parts.len() >= 2 {
                if let Ok(func_idx) = call_parts[1].parse::<usize>() {
                    if func_indices_to_fix.contains(&func_idx) {
                        // Check if next line is "drop"
                        if i + 1 < lines.len() && lines[i + 1].trim() == "drop" {
                            skip_next = true;
                        }
                    }
                }
            }
        }
        final_lines.push(line.to_string());
    }
    fixed_wat = final_lines.join("\n");

    // Convert back to wasm
    let fixed_wasm = wat::parse_str(&fixed_wat)?;

    Ok(fixed_wasm)
}

fn cmd_component(
    wit_path: &Path,
    output: &Path,
    project_name: Option<&str>,
    target: &str,
    release: bool,
    world: Option<&str>,
) -> Result<()> {
    // Step 1: Generate
    eprintln!("=== Step 1: Generate bindings ===");
    cmd_generate(
        wit_path,
        Path::new("."),
        project_name,
        "gen",
        "impl",
        true,
        false,
        "0.1.0",
        world,
        "json", // default pkg format
        false,  // js_string_builtins (TODO: add to Component command)
    )?;

    // Step 2: Build
    eprintln!("\n=== Step 2: Build ===");
    cmd_build(target, release)?;

    // Step 3: Find wasm file
    eprintln!("\n=== Step 3: Componentize ===");
    let wasm_file = find_wasm_file(target, release)?;
    eprintln!("Found: {}", wasm_file.display());

    // Get WIT directory
    let wit_dir = if wit_path.is_dir() {
        wit_path.to_path_buf()
    } else {
        wit_path.parent().unwrap_or(Path::new(".")).to_path_buf()
    };

    cmd_componentize(&wasm_file, &wit_dir, output)?;

    eprintln!("\n=== Complete! ===");
    eprintln!("Component: {}", output.display());
    Ok(())
}

fn cmd_resolve_json(wit_path: &Path, world: Option<&str>) -> Result<()> {
    let mut resolve = Resolve::new();
    apply_wit_features(&mut resolve);
    let (pkg_id, _sources) = resolve.push_path(wit_path)?;

    let world_id = match resolve.select_world(&[pkg_id], world) {
        Ok(id) => Some(id.index()),
        Err(err) => {
            if world.is_some() {
                return Err(err);
            }
            None
        }
    };

    let output = serde_json::json!({
        "resolve": resolve,
        "world_id": world_id,
    });

    println!("{}", serde_json::to_string_pretty(&output)?);
    Ok(())
}

fn cmd_new(name: &str, wit: Option<&Path>) -> Result<()> {
    eprintln!("Creating new MoonBit component project: {}", name);

    let project_dir = Path::new(name);
    if project_dir.exists() {
        bail!("directory '{}' already exists", name);
    }

    // Create directory structure
    std::fs::create_dir_all(project_dir.join("src"))?;
    std::fs::create_dir_all(project_dir.join("wit"))?;

    // Create moon.mod.json
    let moon_mod = serde_json::json!({
        "name": name,
        "version": "0.1.0",
        "deps": {}
    });
    std::fs::write(
        project_dir.join("moon.mod.json"),
        serde_json::to_string_pretty(&moon_mod)?,
    )?;

    // Create moon.pkg.json for src
    let moon_pkg = serde_json::json!({
        "is-main": true,
        "import": []
    });
    std::fs::write(
        project_dir.join("src/moon.pkg.json"),
        serde_json::to_string_pretty(&moon_pkg)?,
    )?;

    // Create sample source
    std::fs::write(
        project_dir.join("src/lib.mbt"),
        r#"///|
fn main {
  println("Hello from MoonBit component!")
}
"#,
    )?;

    // Create or copy WIT file
    if let Some(wit_src) = wit {
        std::fs::copy(
            wit_src,
            project_dir.join("wit").join(wit_src.file_name().unwrap()),
        )?;
    } else {
        std::fs::write(
            project_dir.join("wit/world.wit"),
            format!(
                r#"package local:{name};

world {name} {{
  // Add your exports here
  // export greet: func(name: string) -> string;
}}
"#
            ),
        )?;
    }

    // Create wkg.toml
    let wkg_toml = format!(
        r#"[metadata]
name = "local:{name}"
version = "0.1.0"
# description = ""
# licenses = "MIT"

[dependencies]
# "wasi:http" = "0.2.0"

[overrides]
# "dep:name" = {{ path = "./path/to/wit" }}
"#
    );
    std::fs::write(project_dir.join("wkg.toml"), wkg_toml)?;

    eprintln!("Created project: {}", name);
    eprintln!("\nNext steps:");
    eprintln!("  cd {}", name);
    eprintln!("  moon-component generate wit/world.wit");
    eprintln!("  moon-component build");
    Ok(())
}

fn cmd_init(wit_path: &Path, component_dir: &str, world: Option<&str>) -> Result<()> {
    // Read parent moon.mod.json
    let moon_mod_path = Path::new("moon.mod.json");
    if !moon_mod_path.exists() {
        bail!("moon.mod.json not found. Run this command in a MoonBit project root.");
    }

    let moon_mod_content = std::fs::read_to_string(moon_mod_path)?;
    let moon_mod: serde_json::Value = serde_json::from_str(&moon_mod_content)?;
    let parent_name = moon_mod
        .get("name")
        .and_then(|v| v.as_str())
        .context("moon.mod.json missing 'name' field")?;

    eprintln!(
        "Initializing component in existing project: {}",
        parent_name
    );

    // Check WIT exists
    if !wit_path.exists() {
        bail!(
            "WIT path not found: {}. Create a WIT file first.",
            wit_path.display()
        );
    }

    // Create component directory
    let comp_dir = Path::new(component_dir);
    std::fs::create_dir_all(comp_dir)?;

    // Generate component/moon.mod.json (JSON format required for moon.mod.json)
    let comp_name = format!("{}/component", parent_name);
    let moon_mod_json = serde_json::json!({
        "name": comp_name,
        "version": "0.1.0",
        "deps": {
            parent_name: { "path": ".." }
        }
    });
    std::fs::write(
        comp_dir.join("moon.mod.json"),
        serde_json::to_string_pretty(&moon_mod_json)?,
    )?;
    eprintln!("Created: {}/moon.mod.json", component_dir);

    // Create dist directory
    std::fs::create_dir_all(comp_dir.join("dist"))?;

    // Copy or symlink wit directory into component
    let comp_wit_dir = comp_dir.join("wit");
    if !comp_wit_dir.exists() {
        if wit_path.is_dir() {
            // Copy wit directory
            copy_dir_all(wit_path, &comp_wit_dir)?;
        } else {
            // Create wit dir and copy single file
            std::fs::create_dir_all(&comp_wit_dir)?;
            std::fs::copy(wit_path, comp_wit_dir.join(wit_path.file_name().unwrap()))?;
        }
        eprintln!("Copied WIT to: {}/wit/", component_dir);
    }

    // Generate bindings
    let wit_in_comp = if wit_path.is_dir() {
        comp_wit_dir.clone()
    } else {
        comp_wit_dir.join(wit_path.file_name().unwrap())
    };

    eprintln!("\n=== Generating bindings ===");
    // Use component module name (parent/component) as project_name for correct import paths
    // Use JSON format for now (DSL has parsing issues)
    cmd_generate(
        &wit_in_comp,
        comp_dir,
        Some(&comp_name),
        "gen",
        "impl",
        true, // generate_impl
        true, // wkg
        "0.1.0",
        world,
        "json",
        false, // js_string_builtins (TODO: add to Init command)
    )?;

    eprintln!("\n✅ Component initialized!");
    eprintln!("\nStructure:");
    eprintln!("  {}/", component_dir);
    eprintln!(
        "    ├── moon.mod.json   # deps: {{ {}: {{ path: \"..\" }} }}",
        parent_name
    );
    eprintln!("    ├── wit/            # WIT definitions");
    eprintln!("    ├── gen/            # Generated bindings (auto-regenerated)");
    eprintln!("    ├── impl/           # Your implementation (edit this)");
    eprintln!("    └── dist/           # Build output");
    eprintln!("\nNext steps:");
    eprintln!("  1. Edit impl/*.mbt to implement the interface");
    eprintln!("  2. cd {} && moon-component build", component_dir);
    eprintln!("  3. moon-component componentize (in {}/)", component_dir);

    Ok(())
}

fn cmd_fetch(wit_dir: &Path, output_type: &str, update: bool) -> Result<()> {
    eprintln!("Fetching WIT dependencies from: {}", wit_dir.display());

    // Check if wkg is available
    let wkg_check = Command::new("wkg").arg("--version").output();

    if wkg_check.is_err() {
        bail!("wkg not found. Install with: cargo install wkg");
    }

    // Build command
    let subcommand = if update { "update" } else { "fetch" };
    let mut cmd = Command::new("wkg");
    cmd.arg("wit").arg(subcommand).arg("--wit-dir").arg(wit_dir);

    if !update {
        cmd.arg("--type").arg(output_type);
    }

    eprintln!(
        "Running: wkg wit {} --wit-dir {}",
        subcommand,
        wit_dir.display()
    );

    let status = cmd.status().context("failed to run wkg")?;

    if !status.success() {
        bail!("wkg wit {} failed", subcommand);
    }

    // Check what was fetched
    let deps_dir = wit_dir.join("deps");
    if deps_dir.exists() {
        eprintln!("\n✅ Dependencies fetched to: {}", deps_dir.display());
        for entry in std::fs::read_dir(&deps_dir)? {
            let entry = entry?;
            eprintln!("  - {}", entry.file_name().to_string_lossy());
        }
    }

    let lock_file = wit_dir.join("wkg.lock");
    if lock_file.exists() {
        eprintln!("\nLock file: {}", lock_file.display());
    }

    Ok(())
}

fn copy_dir_all(src: &Path, dst: &Path) -> Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let path = entry.path();
        let dest_path = dst.join(entry.file_name());
        if path.is_dir() {
            copy_dir_all(&path, &dest_path)?;
        } else {
            std::fs::copy(&path, &dest_path)?;
        }
    }
    Ok(())
}

fn find_codegen_root() -> Result<PathBuf> {
    // Find the moon-component project root based on the binary location
    let exe_path = std::env::current_exe()?;
    // Binary is at tools/moon-component/target/release/moon-component
    // Project root is 4 levels up
    let dir = exe_path
        .parent() // release
        .and_then(|p| p.parent()) // target
        .and_then(|p| p.parent()) // moon-component
        .and_then(|p| p.parent()) // tools
        .and_then(|p| p.parent()) // project root
        .map(|p| p.to_path_buf())
        .context("failed to find codegen root from binary path")?;

    // Verify it's the correct project
    if !dir.join("src/main/main.mbt").exists() {
        // Try to find from current dir
        let mut search_dir = std::env::current_dir()?;
        loop {
            if search_dir.join("src/main/main.mbt").exists()
                && search_dir.join("src/codegen.mbt").exists()
            {
                return Ok(search_dir);
            }
            if !search_dir.pop() {
                bail!("could not find moon-component codegen root");
            }
        }
    }

    Ok(dir)
}

fn find_wasm_file(target: &str, release: bool) -> Result<PathBuf> {
    let mode = if release { "release" } else { "debug" };
    let target_dir = Path::new("target").join(target).join(mode).join("build");

    if !target_dir.exists() {
        bail!(
            "build directory not found: {}. Run 'moon-component build' first.",
            target_dir.display()
        );
    }

    // Prefer conventional package outputs
    for name in ["impl", "src"] {
        let preferred = target_dir.join(name).join(format!("{name}.wasm"));
        if preferred.exists() {
            return Ok(preferred);
        }
    }

    // Find .wasm file candidates
    let mut candidates = Vec::new();
    for entry in walkdir(target_dir.clone())? {
        let path = entry;
        if path.extension().map(|e| e == "wasm").unwrap_or(false) {
            // Skip component files
            let name = path.file_name().unwrap().to_string_lossy();
            if !name.contains("component") {
                candidates.push(path);
            }
        }
    }

    match candidates.len() {
        0 => bail!("no .wasm file found in build output"),
        1 => Ok(candidates.remove(0)),
        _ => {
            let list = candidates
                .iter()
                .map(|p| format!("  - {}", p.display()))
                .collect::<Vec<_>>()
                .join("\n");
            bail!(
                "multiple .wasm files found. Use 'moon-component componentize <wasm> --wit-dir <wit>'\n{}",
                list
            );
        }
    }
}

fn walkdir(dir: PathBuf) -> Result<Vec<PathBuf>> {
    let mut results = Vec::new();
    if dir.is_dir() {
        for entry in std::fs::read_dir(&dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                results.extend(walkdir(path)?);
            } else {
                results.push(path);
            }
        }
    }
    Ok(results)
}

fn cmd_wit_from_moonbit(
    pkg_dir: &Path,
    output: &Path,
    namespace: &str,
    name: Option<&str>,
    world: Option<&str>,
    interface: &str,
    check_only: bool,
) -> Result<()> {
    if check_only {
        eprintln!(
            "Checking WIT compatibility for MoonBit package: {}",
            pkg_dir.display()
        );
    } else {
        eprintln!("Generating WIT from MoonBit package: {}", pkg_dir.display());
    }

    // Run moon info to generate mbti files
    let status = Command::new("moon")
        .args(["info", "--directory", &pkg_dir.to_string_lossy()])
        .status()
        .context("failed to run moon info")?;

    if !status.success() {
        bail!("moon info failed");
    }

    // Find pkg.generated.mbti file
    let mbti_path = pkg_dir.join("src/pkg.generated.mbti");
    if !mbti_path.exists() {
        // Try looking in subdirectories
        let mut found = None;
        for entry in walkdir(pkg_dir.to_path_buf())? {
            if entry.file_name().map(|s| s.to_str()) == Some(Some("pkg.generated.mbti")) {
                found = Some(entry);
                break;
            }
        }
        if let Some(path) = found {
            return parse_mbti_and_generate_wit(
                &path, output, namespace, name, world, interface, check_only,
            );
        }
        bail!("Could not find pkg.generated.mbti in {}", pkg_dir.display());
    }

    parse_mbti_and_generate_wit(
        &mbti_path, output, namespace, name, world, interface, check_only,
    )
}

/// Validation error for WIT compatibility
#[derive(Debug)]
struct ValidationError {
    location: String,
    message: String,
}

impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.location, self.message)
    }
}

fn parse_mbti_and_generate_wit(
    mbti_path: &Path,
    output: &Path,
    namespace: &str,
    name: Option<&str>,
    world: Option<&str>,
    interface: &str,
    check_only: bool,
) -> Result<()> {
    let content = std::fs::read_to_string(mbti_path)?;

    let pkg_name = name.unwrap_or("component");
    let world_name = world.unwrap_or(pkg_name);

    let mut errors: Vec<ValidationError> = Vec::new();
    let mut warnings: Vec<ValidationError> = Vec::new();
    let mut defined_types: Vec<String> = Vec::new();

    // Check for Exports trait
    let has_exports_trait = content.contains("pub(open) trait Exports {");
    if !has_exports_trait {
        errors.push(ValidationError {
            location: mbti_path.display().to_string(),
            message: "Missing `pub(open) trait Exports { ... }`. Define an Exports trait to specify the component interface.".to_string(),
        });
    }

    let mut wit = String::new();
    wit.push_str(&format!("package {namespace}:{pkg_name};\n\n"));

    // Parse types (structs and enums)
    let mut types_wit = String::new();
    let mut in_struct = false;
    let mut in_enum = false;
    let mut current_type = String::new();
    let mut struct_fields: Vec<(String, String)> = Vec::new();
    let mut enum_cases: Vec<String> = Vec::new();
    let mut line_num = 0;

    for line in content.lines() {
        line_num += 1;
        let trimmed = line.trim();

        // Parse struct
        if trimmed.starts_with("pub(all) struct ") && trimmed.ends_with("{") {
            let name_part = trimmed
                .strip_prefix("pub(all) struct ")
                .unwrap()
                .strip_suffix(" {")
                .unwrap();
            current_type = name_part.to_string();
            defined_types.push(current_type.clone());
            in_struct = true;
            struct_fields.clear();
            continue;
        }

        // Check for non-pub(all) struct
        if (trimmed.starts_with("pub struct ")
            || trimmed.starts_with("priv struct ")
            || (trimmed.starts_with("struct ") && !trimmed.starts_with("pub(all) struct ")))
            && trimmed.ends_with("{")
        {
            let name_part = if let Some(s) = trimmed.strip_prefix("pub struct ") {
                s
            } else if let Some(s) = trimmed.strip_prefix("priv struct ") {
                s
            } else {
                trimmed.strip_prefix("struct ").unwrap_or(trimmed)
            };
            let name_part = name_part.strip_suffix(" {").unwrap_or(name_part);
            warnings.push(ValidationError {
                location: format!("{}:{}", mbti_path.display(), line_num),
                message: format!(
                    "Struct `{}` is not `pub(all)`. Use `pub(all) struct {}` to export it to WIT.",
                    name_part, name_part
                ),
            });
        }

        if in_struct {
            if trimmed == "}" {
                // Validate struct fields
                for (field_name, field_type) in &struct_fields {
                    if let Some(err) = validate_wit_type(field_type, &defined_types) {
                        errors.push(ValidationError {
                            location: format!(
                                "{}:{} (struct {}.{})",
                                mbti_path.display(),
                                line_num,
                                current_type,
                                field_name
                            ),
                            message: err,
                        });
                    }
                }

                // Emit record
                types_wit.push_str(&format!("  record {} {{\n", to_kebab_case(&current_type)));
                for (field_name, field_type) in &struct_fields {
                    let wit_type = moonbit_type_to_wit(field_type);
                    types_wit.push_str(&format!(
                        "    {}: {},\n",
                        to_kebab_case(field_name),
                        wit_type
                    ));
                }
                types_wit.push_str("  }\n\n");
                in_struct = false;
            } else if trimmed.contains(" : ") {
                // Parse field: "name : Type"
                let parts: Vec<&str> = trimmed.split(" : ").collect();
                if parts.len() == 2 {
                    let field_name = parts[0].trim();
                    let field_type = parts[1].trim();
                    struct_fields.push((field_name.to_string(), field_type.to_string()));
                }
            }
            continue;
        }

        // Parse enum
        if trimmed.starts_with("pub(all) enum ") && trimmed.ends_with("{") {
            let name_part = trimmed
                .strip_prefix("pub(all) enum ")
                .unwrap()
                .strip_suffix(" {")
                .unwrap();
            current_type = name_part.to_string();
            defined_types.push(current_type.clone());
            in_enum = true;
            enum_cases.clear();
            continue;
        }

        // Check for non-pub(all) enum
        if (trimmed.starts_with("pub enum ")
            || trimmed.starts_with("priv enum ")
            || (trimmed.starts_with("enum ") && !trimmed.starts_with("pub(all) enum ")))
            && trimmed.ends_with("{")
        {
            let name_part = if let Some(s) = trimmed.strip_prefix("pub enum ") {
                s
            } else if let Some(s) = trimmed.strip_prefix("priv enum ") {
                s
            } else {
                trimmed.strip_prefix("enum ").unwrap_or(trimmed)
            };
            let name_part = name_part.strip_suffix(" {").unwrap_or(name_part);
            warnings.push(ValidationError {
                location: format!("{}:{}", mbti_path.display(), line_num),
                message: format!(
                    "Enum `{}` is not `pub(all)`. Use `pub(all) enum {}` to export it to WIT.",
                    name_part, name_part
                ),
            });
        }

        if in_enum {
            if trimmed == "}" {
                // Check if all cases are const (no payload)
                let has_payload = enum_cases.iter().any(|c| c.contains('('));

                if has_payload {
                    // Enum with payload - error (WIT enum must be const-only)
                    errors.push(ValidationError {
                        location: format!("{}:{}", mbti_path.display(), line_num),
                        message: format!(
                            "Enum `{}` has cases with payload. WIT enum must be const-only (no payload). Cases with payload: {}",
                            current_type,
                            enum_cases.iter().filter(|c| c.contains('(')).cloned().collect::<Vec<_>>().join(", ")
                        ),
                    });
                }

                // Emit WIT enum (const-only)
                types_wit.push_str(&format!("  enum {} {{\n", to_kebab_case(&current_type)));
                for case in &enum_cases {
                    // Only emit const cases (no payload)
                    if !case.contains('(') {
                        types_wit.push_str(&format!("    {},\n", case));
                    }
                }
                types_wit.push_str("  }\n\n");
                in_enum = false;
            } else if !trimmed.is_empty() {
                // Check if case has payload
                if trimmed.contains('(') {
                    // Validate payload types for better error messages
                    let paren_pos = trimmed.find('(').unwrap();
                    let types_str = trimmed[paren_pos + 1..].trim_end_matches(')');
                    for ty in types_str.split(", ") {
                        if let Some(err) = validate_wit_type(ty.trim(), &defined_types) {
                            errors.push(ValidationError {
                                location: format!(
                                    "{}:{} (enum {}.{})",
                                    mbti_path.display(),
                                    line_num,
                                    current_type,
                                    trimmed
                                ),
                                message: err,
                            });
                        }
                    }
                }

                // Parse case (store original for error reporting)
                let case_wit = parse_enum_case(trimmed);
                enum_cases.push(case_wit);
            }
            continue;
        }
    }

    // Parse trait methods
    let mut methods_wit = String::new();
    let mut in_trait = false;
    let mut method_count = 0;
    line_num = 0;

    for line in content.lines() {
        line_num += 1;
        let trimmed = line.trim();

        if trimmed.starts_with("pub(open) trait Exports {") {
            in_trait = true;
            continue;
        }

        if in_trait {
            if trimmed == "}" {
                break;
            }

            if !trimmed.is_empty() && trimmed.contains("(Self") {
                method_count += 1;

                // Validate method signature
                if let Some(err) = validate_trait_method(trimmed, &defined_types) {
                    errors.push(ValidationError {
                        location: format!("{}:{}", mbti_path.display(), line_num),
                        message: err,
                    });
                }

                // Parse method: "method_name(Self, Type1, Type2) -> ReturnType"
                if let Some(method_wit) = parse_trait_method(trimmed) {
                    methods_wit.push_str(&format!("  {};\n", method_wit));
                }
            }
        }
    }

    if has_exports_trait && method_count == 0 {
        warnings.push(ValidationError {
            location: mbti_path.display().to_string(),
            message: "Exports trait has no methods. Add methods to define the component interface."
                .to_string(),
        });
    }

    // Print validation results
    if !warnings.is_empty() {
        eprintln!("\n⚠️  Warnings ({}):", warnings.len());
        for w in &warnings {
            eprintln!("  {}", w);
        }
    }

    if !errors.is_empty() {
        eprintln!("\n❌ Errors ({}):", errors.len());
        for e in &errors {
            eprintln!("  {}", e);
        }
        bail!(
            "WIT compatibility check failed with {} error(s)",
            errors.len()
        );
    }

    if check_only {
        eprintln!("\n✅ WIT compatibility check passed!");
        eprintln!(
            "   {} type(s), {} method(s) found",
            defined_types.len(),
            method_count
        );
        return Ok(());
    }

    // Build interface
    wit.push_str(&format!("interface {interface} {{\n"));
    wit.push_str(&types_wit);
    wit.push_str(&methods_wit);
    wit.push_str("}\n\n");

    // Build world
    wit.push_str(&format!("world {world_name} {{\n"));
    wit.push_str(&format!("  export {interface};\n"));
    wit.push_str("}\n");

    // Write output
    if let Some(parent) = output.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(output, &wit)?;

    eprintln!("\n✅ Generated: {}", output.display());
    eprintln!("\n{}", wit);

    Ok(())
}

/// Validate if a MoonBit type can be converted to WIT
fn validate_wit_type(ty: &str, defined_types: &[String]) -> Option<String> {
    let ty = ty.trim();

    // Handle optional: "Type?"
    if ty.ends_with('?') {
        let inner = &ty[..ty.len() - 1];
        return validate_wit_type(inner, defined_types);
    }

    // Handle Result[T, E]
    if ty.starts_with("Result[") {
        let inner = ty.strip_prefix("Result[")?.strip_suffix(']')?;
        let parts: Vec<&str> = inner.split(", ").collect();
        if parts.len() == 2 {
            if let Some(err) = validate_wit_type(parts[0], defined_types) {
                return Some(err);
            }
            return validate_wit_type(parts[1], defined_types);
        }
        return Some(format!("Invalid Result type: {}", ty));
    }

    // Handle Array[T]
    if ty.starts_with("Array[") {
        let inner = ty.strip_prefix("Array[")?.strip_suffix(']')?;
        return validate_wit_type(inner, defined_types);
    }

    // Handle Option[T]
    if ty.starts_with("Option[") {
        let inner = ty.strip_prefix("Option[")?.strip_suffix(']')?;
        return validate_wit_type(inner, defined_types);
    }

    // Primitive types
    match ty {
        "Int" | "Int64" | "UInt" | "UInt64" | "Float" | "Double" | "Bool" | "Char" | "String"
        | "Unit" => None,
        _ => {
            // Check if it's a defined type
            if defined_types.contains(&ty.to_string()) {
                None
            } else {
                // Check for unsupported types
                if ty.contains("->") || ty.contains("Fn") || ty.contains("fn") {
                    Some(format!("Function types are not supported in WIT: {}", ty))
                } else if ty.starts_with("&") || ty.starts_with("Ref[") {
                    Some(format!("Reference types are not supported in WIT: {}", ty))
                } else if ty.contains("Map[") || ty.contains("HashMap[") {
                    Some(format!(
                        "Map types are not directly supported in WIT. Use list<tuple<K, V>> instead: {}",
                        ty
                    ))
                } else {
                    // Assume it's a custom type that will be defined
                    None
                }
            }
        }
    }
}

/// Validate a trait method signature
fn validate_trait_method(line: &str, defined_types: &[String]) -> Option<String> {
    let line = line.trim();

    // Check for Self parameter
    if !line.contains("(Self") {
        return Some("Method must have Self as first parameter".to_string());
    }

    // Parse parameters
    let paren_pos = line.find('(')?;
    let close_paren = line.find(')')?;
    let params_str = &line[paren_pos + 1..close_paren];

    for param in params_str.split(", ") {
        if param == "Self" {
            continue;
        }
        if let Some(err) = validate_wit_type(param.trim(), defined_types) {
            return Some(format!("Invalid parameter type: {}", err));
        }
    }

    // Parse return type
    if line.contains(" -> ") {
        let parts: Vec<&str> = line.split(" -> ").collect();
        if parts.len() == 2 {
            if let Some(err) = validate_wit_type(parts[1].trim(), defined_types) {
                return Some(format!("Invalid return type: {}", err));
            }
        }
    }

    None
}

fn parse_enum_case(case: &str) -> String {
    // Handle: "CaseName" or "CaseName(Type1, Type2)"
    if let Some(paren_pos) = case.find('(') {
        let name = &case[..paren_pos];
        let types_str = case[paren_pos + 1..].trim_end_matches(')');
        let types: Vec<&str> = types_str.split(", ").collect();

        if types.len() == 1 && !types[0].is_empty() {
            format!("{}({})", to_kebab_case(name), moonbit_type_to_wit(types[0]))
        } else if types.len() > 1 {
            let wit_types: Vec<String> = types.iter().map(|t| moonbit_type_to_wit(t)).collect();
            format!("{}(tuple<{}>)", to_kebab_case(name), wit_types.join(", "))
        } else {
            to_kebab_case(name)
        }
    } else {
        to_kebab_case(case)
    }
}

fn parse_trait_method(line: &str) -> Option<String> {
    // Parse: "method_name(Self, Type1, Type2) -> ReturnType"
    let line = line.trim();
    if line.is_empty() || !line.contains("(Self") {
        return None;
    }

    let paren_pos = line.find('(')?;
    let method_name = &line[..paren_pos];

    let close_paren = line.find(')')?;
    let params_str = &line[paren_pos + 1..close_paren];

    // Parse parameters (skip Self)
    let params: Vec<&str> = params_str.split(", ").collect();
    let mut wit_params: Vec<String> = Vec::new();

    for (i, param) in params.iter().enumerate() {
        if *param == "Self" {
            continue;
        }
        wit_params.push(format!("p{}: {}", i, moonbit_type_to_wit(param)));
    }

    // Parse return type
    let return_type = if line.contains(" -> ") {
        let parts: Vec<&str> = line.split(" -> ").collect();
        if parts.len() == 2 {
            moonbit_type_to_wit(parts[1])
        } else {
            "".to_string()
        }
    } else {
        "".to_string()
    };

    let params_str = wit_params.join(", ");
    if return_type.is_empty() {
        Some(format!(
            "{}: func({})",
            to_kebab_case(method_name),
            params_str
        ))
    } else {
        Some(format!(
            "{}: func({}) -> {}",
            to_kebab_case(method_name),
            params_str,
            return_type
        ))
    }
}

fn moonbit_type_to_wit(ty: &str) -> String {
    let ty = ty.trim();

    // Handle optional: "Type?"
    if ty.ends_with('?') {
        let inner = &ty[..ty.len() - 1];
        return format!("option<{}>", moonbit_type_to_wit(inner));
    }

    // Handle Result[T, E]
    if ty.starts_with("Result[") {
        let inner = ty
            .strip_prefix("Result[")
            .unwrap()
            .strip_suffix(']')
            .unwrap();
        let parts: Vec<&str> = inner.split(", ").collect();
        if parts.len() == 2 {
            return format!(
                "result<{}, {}>",
                moonbit_type_to_wit(parts[0]),
                moonbit_type_to_wit(parts[1])
            );
        }
    }

    // Handle Array[T]
    if ty.starts_with("Array[") {
        let inner = ty
            .strip_prefix("Array[")
            .unwrap()
            .strip_suffix(']')
            .unwrap();
        return format!("list<{}>", moonbit_type_to_wit(inner));
    }

    // Handle Option[T]
    if ty.starts_with("Option[") {
        let inner = ty
            .strip_prefix("Option[")
            .unwrap()
            .strip_suffix(']')
            .unwrap();
        return format!("option<{}>", moonbit_type_to_wit(inner));
    }

    // Primitive types
    match ty {
        "Int" => "s32".to_string(),
        "Int64" => "s64".to_string(),
        "UInt" => "u32".to_string(),
        "UInt64" => "u64".to_string(),
        "Float" => "f32".to_string(),
        "Double" => "f64".to_string(),
        "Bool" => "bool".to_string(),
        "Char" => "char".to_string(),
        "String" => "string".to_string(),
        "Unit" => "".to_string(),
        _ => to_kebab_case(ty), // Custom types
    }
}

fn cmd_plug(socket: &Path, plugs: &[PathBuf], output: &Path) -> Result<()> {
    // Check if wac is available
    let wac_check = Command::new("wac").arg("--version").output();
    if wac_check.is_err() {
        bail!("wac is not installed. Install it with: cargo install wac-cli");
    }

    println!("Plugging components...");
    println!("  Socket: {}", socket.display());
    for plug in plugs {
        println!("  Plug: {}", plug.display());
    }

    // Build wac plug command
    let mut cmd = Command::new("wac");
    cmd.arg("plug");

    // Add plug components
    for plug in plugs {
        cmd.arg("--plug").arg(plug);
    }

    // Add socket and output
    cmd.arg(socket);
    cmd.arg("-o").arg(output);

    let status = cmd.status().context("failed to run wac plug")?;
    if !status.success() {
        bail!("wac plug failed");
    }

    println!("Composed component: {}", output.display());
    Ok(())
}

fn cmd_compose(wac_file: &Path, output: &Path) -> Result<()> {
    run_wac_compose(wac_file, output, None)
}

fn run_wac_compose(wac_file: &Path, output: &Path, deps_dir: Option<&Path>) -> Result<()> {
    // Check if wac is available
    let wac_check = Command::new("wac").arg("--version").output();
    if wac_check.is_err() {
        bail!("wac is not installed. Install it with: cargo install wac-cli");
    }

    println!("Composing components using: {}", wac_file.display());

    let mut cmd = Command::new("wac");
    cmd.arg("compose").arg(wac_file).arg("-o").arg(output);

    if let Some(deps) = deps_dir {
        cmd.arg("--deps-dir").arg(deps);
    }

    let status = cmd.status().context("failed to run wac compose")?;

    if !status.success() {
        bail!("wac compose failed");
    }

    println!("Composed component: {}", output.display());
    Ok(())
}

fn run_wac_plug(socket: &Path, plugs: &[PathBuf], output: &Path) -> Result<()> {
    // Check if wac is available
    let wac_check = Command::new("wac").arg("--version").output();
    if wac_check.is_err() {
        bail!("wac is not installed. Install it with: cargo install wac-cli");
    }

    let mut cmd = Command::new("wac");
    cmd.arg("plug");

    for plug in plugs {
        cmd.arg("--plug").arg(plug);
    }

    cmd.arg(socket).arg("-o").arg(output);

    let status = cmd.status().context("failed to run wac plug")?;

    if !status.success() {
        bail!("wac plug failed");
    }

    println!("Composed component: {}", output.display());
    Ok(())
}

// Bundle configuration types
#[derive(serde::Deserialize, Debug)]
struct BundleConfig {
    bundle: BundleSettings,
    #[serde(default)]
    dependencies: std::collections::HashMap<String, DependencySpec>,
    #[serde(default)]
    build: BuildSettings,
}

#[derive(serde::Deserialize, Debug)]
struct BundleSettings {
    name: String,
    #[serde(default = "default_output")]
    output: PathBuf,
    entry: String,
}

/// Dependency specification - MoonBit path only
#[derive(serde::Deserialize, Debug, Clone)]
#[serde(untagged)]
enum DependencySpec {
    /// MoonBit local path: { path = "libs/math" }
    MoonBit { path: String },
    /// Prebuilt component: { component = "path/to/component.wasm" }
    Component { component: String },
    /// Simple path: "libs/math"
    Simple(String),
}

#[derive(serde::Deserialize, Debug, Default)]
struct BuildSettings {
    #[serde(default = "default_target")]
    target: String,
    #[serde(default)]
    release: bool,
}

fn default_output() -> PathBuf {
    PathBuf::from("dist/composed.wasm")
}

fn default_target() -> String {
    "wasm".to_string()
}

/// Resolved dependency with its built wasm path
#[derive(Debug)]
struct ResolvedDep {
    wasm_path: PathBuf,
}

/// Resolve a single dependency (MoonBit only)
fn resolve_dependency(
    name: &str,
    spec: &DependencySpec,
    config_dir: &Path,
    deps_dir: &Path,
    build_settings: &BuildSettings,
    dry_run: bool,
) -> Result<ResolvedDep> {
    match spec {
        DependencySpec::Component { component } => {
            let component_path = {
                let p = PathBuf::from(component);
                if p.is_absolute() {
                    p
                } else {
                    config_dir.join(p)
                }
            };
            if !component_path.exists() {
                bail!(
                    "Component not found for {}: {}",
                    name,
                    component_path.display()
                );
            }
            println!("  [component] {} -> {}", name, component_path.display());
            Ok(ResolvedDep {
                wasm_path: component_path,
            })
        }
        DependencySpec::MoonBit { path } | DependencySpec::Simple(path) => {
            // Determine output path for this dependency
            let parts: Vec<&str> = name.split(':').collect();
            let output_path = if parts.len() == 2 {
                let ns_dir = deps_dir.join(parts[0]);
                std::fs::create_dir_all(&ns_dir)?;
                deps_dir.join(format!("{}/{}.wasm", parts[0], parts[1]))
            } else {
                deps_dir.join(format!("{}.wasm", name.replace(':', "_")))
            };

            resolve_moonbit_dep(
                name,
                path,
                config_dir,
                &output_path,
                build_settings,
                dry_run,
            )?;

            Ok(ResolvedDep {
                wasm_path: output_path,
            })
        }
    }
}

/// Build MoonBit component
fn resolve_moonbit_dep(
    name: &str,
    path: &str,
    config_dir: &Path,
    output_path: &Path,
    build_settings: &BuildSettings,
    dry_run: bool,
) -> Result<()> {
    let component_path = config_dir.join(path);
    let wit_path = component_path.join("wit");

    if !wit_path.exists() {
        bail!(
            "WIT directory not found for {}: {}",
            name,
            wit_path.display()
        );
    }

    println!("  [moonbit] {} -> {}", name, output_path.display());

    if dry_run {
        return Ok(());
    }

    // Run moon build
    let mut moon_cmd = Command::new("moon");
    moon_cmd
        .arg("build")
        .arg("--target")
        .arg(&build_settings.target)
        .arg("--directory")
        .arg(&component_path);

    if build_settings.release {
        moon_cmd.arg("--release");
    }

    let status = moon_cmd.status().context("failed to run moon build")?;
    if !status.success() {
        bail!("moon build failed for {}", name);
    }

    // Find the built wasm
    let build_mode = if build_settings.release {
        "release"
    } else {
        "debug"
    };
    let wasm_path = component_path
        .join("_build")
        .join(&build_settings.target)
        .join(build_mode)
        .join("build")
        .join("impl")
        .join("impl.wasm");

    if !wasm_path.exists() {
        bail!("Built wasm not found for {}: {}", name, wasm_path.display());
    }

    // Componentize
    cmd_componentize(&wasm_path, &wit_path, output_path)?;

    Ok(())
}

fn cmd_bundle(config_path: &Path, build_only: bool, dry_run: bool) -> Result<()> {
    // Read config file
    let config_content = std::fs::read_to_string(config_path)
        .with_context(|| format!("failed to read config: {}", config_path.display()))?;

    let config: BundleConfig = toml::from_str(&config_content)
        .with_context(|| format!("failed to parse config: {}", config_path.display()))?;

    let config_dir = config_path.parent().unwrap_or(Path::new("."));
    let build_dir = config_dir.join("_build").join("bundle");
    let deps_dir = build_dir.join("deps");

    // Create build directories
    std::fs::create_dir_all(&deps_dir)?;

    println!("Bundle: {}", config.bundle.name);
    println!("  Entry: {}", config.bundle.entry);
    println!("  Dependencies: {}", config.dependencies.len());

    // Phase 1: Resolve dependencies
    println!("\n=== Phase 1: Resolve Dependencies ===");

    let mut resolved_deps: Vec<ResolvedDep> = Vec::new();

    for (name, spec) in &config.dependencies {
        let resolved =
            resolve_dependency(name, spec, config_dir, &deps_dir, &config.build, dry_run)?;
        resolved_deps.push(resolved);
    }

    // Phase 2: Build entry component
    println!("\n=== Phase 2: Build Entry ===");

    let entry_wasm = build_dir.join("entry.wasm");

    // Build entry as MoonBit component
    resolve_moonbit_dep(
        "entry",
        &config.bundle.entry,
        config_dir,
        &entry_wasm,
        &config.build,
        dry_run,
    )?;

    if build_only {
        println!("\nBuild complete (--build-only specified, skipping compose)");
        return Ok(());
    }

    // Phase 3: Compose components
    println!("\n=== Phase 3: Compose ===");

    // Output path
    let output_path = config_dir.join(&config.bundle.output);
    if let Some(parent) = output_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // Collect all dependency wasm paths
    let plug_paths: Vec<PathBuf> = resolved_deps.iter().map(|d| d.wasm_path.clone()).collect();

    if dry_run {
        println!("\nWould compose: \\");
        for plug in &plug_paths {
            println!("  --plug {} \\", plug.display());
        }
        println!("  {} -o {}", entry_wasm.display(), output_path.display());
        return Ok(());
    }

    println!("Composing components...");
    run_wac_plug(&entry_wasm, &plug_paths, &output_path)?;

    println!("\n=== Bundle Complete ===");
    println!("Output: {}", output_path.display());

    // Print summary
    let output_size = std::fs::metadata(&output_path)?.len();
    println!(
        "Size: {} bytes ({:.1} KB)",
        output_size,
        output_size as f64 / 1024.0
    );

    Ok(())
}

fn _generate_wac(config: &BundleConfig, _build_dir: &Path) -> Result<String> {
    // Reserved for future use with wac compose
    let mut wac = String::new();

    // Package declaration
    wac.push_str(&format!(
        "package {}:composed;\n\n",
        config.bundle.name.replace('/', ":")
    ));

    // Instantiate dependencies
    for (name, _) in &config.dependencies {
        let var_name = name.replace(':', "-").replace('/', "-");
        wac.push_str(&format!("let {} = new {} {{}};\n", var_name, name));
    }

    wac.push('\n');

    // Instantiate entry with dependencies
    wac.push_str("let entry = new entry:component {\n");
    for (name, _) in &config.dependencies {
        let var_name = name.replace(':', "-").replace('/', "-");
        wac.push_str(&format!("  {}...,\n", var_name));
    }
    wac.push_str("};\n\n");

    wac.push_str("export entry...;\n");

    Ok(wac)
}

fn to_kebab_case(s: &str) -> String {
    let mut result = String::new();
    for (i, c) in s.chars().enumerate() {
        if c == '_' {
            result.push('-');
        } else if c.is_uppercase() {
            if i > 0 && !result.ends_with('-') {
                result.push('-');
            }
            result.push(c.to_ascii_lowercase());
        } else {
            result.push(c);
        }
    }
    result
}
