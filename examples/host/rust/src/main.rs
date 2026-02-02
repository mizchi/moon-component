// Rust host for testing MoonBit guest component

use anyhow::Result;
use wasmtime::component::{Component, Linker, Val};
use wasmtime::{Config, Engine, Store};

mod import_test;
mod types_bench;
mod types_test;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: rust-host <test-type> [component-path]");
        eprintln!("  test-type: guest | import | types | bench");
        std::process::exit(1);
    }

    let test_type = &args[1];

    match test_type.as_str() {
        "guest" => {
            let component_path = args.get(2)
                .map(|s| s.as_str())
                .unwrap_or("../../hello/hello.component.wasm");
            run_guest_test(component_path)
        }
        "import" => {
            let component_path = args.get(2)
                .map(|s| s.as_str())
                .unwrap_or("../../tests/import-test/import-test.component.wasm");
            import_test::run_import_test(component_path)
        }
        "types" => {
            let component_path = args.get(2)
                .map(|s| s.as_str())
                .unwrap_or("../../tests/types-test/types-test.component.wasm");
            types_test::run_types_test(component_path)
        }
        "bench" => {
            let component_path = args.get(2)
                .map(|s| s.as_str())
                .unwrap_or("../../tests/types-test/types-test.component.wasm");
            types_bench::run_types_bench(component_path)
        }
        _ => {
            eprintln!("Unknown test type: {}", test_type);
            std::process::exit(1);
        }
    }
}

fn run_guest_test(component_path: &str) -> Result<()> {
    // Enable component model
    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = Engine::new(&config)?;

    println!("Loading component: {}", component_path);
    let component = Component::from_file(&engine, component_path)?;

    // Create linker and store
    let linker = Linker::<()>::new(&engine);
    let mut store = Store::new(&engine, ());

    // Instantiate
    let instance = linker.instantiate(&mut store, &component)?;

    // Get the exported interface instance, then get greet function from it
    let greet_interface = instance
        .get_export(&mut store, None, "local:hello/greet")
        .expect("greet interface not found");

    let greet_func_export = instance
        .get_export(&mut store, Some(&greet_interface), "greet")
        .expect("greet function not found");

    let greet_func = instance
        .get_func(&mut store, &greet_func_export)
        .expect("could not get greet function");

    // Call greet with "World"
    let mut results = vec![Val::String("".into())];
    greet_func.call(&mut store, &[Val::String("World".into())], &mut results)?;

    // Extract result before post_return
    let result_str = if let Val::String(result) = &results[0] {
        result.to_string()
    } else {
        anyhow::bail!("Unexpected result type");
    };

    // Must call post_return after reading results
    greet_func.post_return(&mut store)?;

    println!("Result: {}", result_str);
    assert_eq!(result_str, "Hello, World!");
    println!("Guest test PASSED!");

    Ok(())
}
