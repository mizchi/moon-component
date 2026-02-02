// Rust host for testing MoonBit import functionality

use anyhow::Result;
use wasmtime::component::{Component, Linker, Val};
use wasmtime::{Config, Engine, Store};

pub fn run_import_test(component_path: &str) -> Result<()> {
    // Enable component model
    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = Engine::new(&config)?;

    println!("Loading component: {}", component_path);
    let component = Component::from_file(&engine, component_path)?;

    // Create linker and store
    let mut linker = Linker::<()>::new(&engine);

    // Add the greet-provider import
    let mut provider = linker.instance("local:import-test/greet-provider")?;
    provider.func_new(
        "get-greeting",
        |mut _store, params: &[Val], results: &mut [Val]| {
            if let Val::String(name) = &params[0] {
                let greeting = format!("Hello from Rust, {}!", name);
                results[0] = Val::String(greeting.into());
            }
            Ok(())
        },
    )?;

    let mut store = Store::new(&engine, ());

    // Instantiate
    let instance = linker.instantiate(&mut store, &component)?;

    // Get the exported interface instance, then get run function
    let consumer_interface = instance
        .get_export(&mut store, None, "local:import-test/greet-consumer")
        .expect("greet-consumer interface not found");

    let run_func_export = instance
        .get_export(&mut store, Some(&consumer_interface), "run")
        .expect("run function not found");

    let run_func = instance
        .get_func(&mut store, &run_func_export)
        .expect("could not get run function");

    // Call run
    let mut results = vec![Val::String("".into())];
    run_func.call(&mut store, &[], &mut results)?;

    // Extract result before post_return
    let result_str = if let Val::String(result) = &results[0] {
        result.to_string()
    } else {
        anyhow::bail!("Unexpected result type");
    };

    run_func.post_return(&mut store)?;

    println!("Result: {}", result_str);
    assert_eq!(result_str, "Hello from Rust, MoonBit!");
    println!("Import test PASSED!");

    Ok(())
}
