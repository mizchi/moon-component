// Benchmarks for WIT types

use anyhow::Result;
use std::time::{Duration, Instant};
use wasmtime::component::{Component, Linker, Val};
use wasmtime::{Config, Engine, Store};

const WARMUP_ITERATIONS: u32 = 100;
const BENCH_ITERATIONS: u32 = 10000;

pub fn run_types_bench(component_path: &str) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    config.wasm_function_references(true);
    let engine = Engine::new(&config)?;

    println!("Loading component: {}", component_path);
    let component = Component::from_file(&engine, component_path)?;

    let linker = Linker::<()>::new(&engine);
    let mut store = Store::new(&engine, ());

    let instance = linker.instantiate(&mut store, &component)?;

    println!("\nBenchmarking {} iterations (warmup: {})\n", BENCH_ITERATIONS, WARMUP_ITERATIONS);
    println!("{:<40} {:>12} {:>12} {:>12}", "Function", "Total (ms)", "Avg (µs)", "Ops/sec");
    println!("{}", "-".repeat(80));

    // Primitives
    bench_echo_s32(&instance, &mut store)?;
    bench_echo_s64(&instance, &mut store)?;
    bench_echo_f32(&instance, &mut store)?;
    bench_echo_bool(&instance, &mut store)?;
    bench_echo_string(&instance, &mut store)?;

    println!();

    // Enums
    bench_echo_color(&instance, &mut store)?;
    bench_color_name(&instance, &mut store)?;

    println!();

    // Flags
    bench_has_read(&instance, &mut store)?;
    bench_echo_permissions(&instance, &mut store)?;

    println!();

    // Containers
    bench_sum_list(&instance, &mut store)?;
    bench_count_list(&instance, &mut store)?;
    bench_divide_ok(&instance, &mut store)?;
    bench_divide_err(&instance, &mut store)?;

    println!();

    // Multi-params
    bench_add2(&instance, &mut store)?;
    bench_add4(&instance, &mut store)?;
    bench_concat3(&instance, &mut store)?;
    bench_mixed_params(&instance, &mut store)?;

    println!();

    // Side-effects
    bench_no_return(&instance, &mut store)?;
    bench_no_params_no_return(&instance, &mut store)?;

    println!("\nBenchmark complete!");
    Ok(())
}

fn print_result(name: &str, duration: Duration) {
    let total_ms = duration.as_secs_f64() * 1000.0;
    let avg_us = (duration.as_nanos() as f64) / (BENCH_ITERATIONS as f64) / 1000.0;
    let ops_per_sec = (BENCH_ITERATIONS as f64) / duration.as_secs_f64();
    println!("{:<40} {:>12.2} {:>12.2} {:>12.0}", name, total_ms, avg_us, ops_per_sec);
}

fn bench_echo_s32(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/primitives").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "echo-s32").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::S32(0)];
    let args = [Val::S32(42)];

    // Warmup
    for _ in 0..WARMUP_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    // Bench
    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("echo-s32(42)", duration);
    Ok(())
}

fn bench_echo_s64(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/primitives").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "echo-s64").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::S64(0)];
    let args = [Val::S64(9999999999i64)];

    for _ in 0..WARMUP_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("echo-s64(9999999999)", duration);
    Ok(())
}

fn bench_echo_f32(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/primitives").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "echo-f32").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::Float32(0.0)];
    let args = [Val::Float32(3.14)];

    for _ in 0..WARMUP_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("echo-f32(3.14)", duration);
    Ok(())
}

fn bench_echo_bool(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/primitives").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "echo-bool").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::Bool(false)];
    let args = [Val::Bool(true)];

    for _ in 0..WARMUP_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("echo-bool(true)", duration);
    Ok(())
}

fn bench_echo_string(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/primitives").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "echo-string").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::String("".into())];

    for _ in 0..WARMUP_ITERATIONS {
        let args = [Val::String("hello".into())];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        let args = [Val::String("hello".into())];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("echo-string(\"hello\")", duration);
    Ok(())
}

fn bench_echo_color(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/enums").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "echo-color").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::Enum("".into())];

    for _ in 0..WARMUP_ITERATIONS {
        let args = [Val::Enum("red".into())];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        let args = [Val::Enum("red".into())];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("echo-color(red)", duration);
    Ok(())
}

fn bench_color_name(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/enums").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "color-name").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::String("".into())];

    for _ in 0..WARMUP_ITERATIONS {
        let args = [Val::Enum("blue".into())];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        let args = [Val::Enum("blue".into())];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("color-name(blue)", duration);
    Ok(())
}

fn bench_has_read(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/flags-test").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "has-read").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::Bool(false)];

    for _ in 0..WARMUP_ITERATIONS {
        let args = [Val::Flags(vec!["read".into(), "write".into()])];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        let args = [Val::Flags(vec!["read".into(), "write".into()])];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("has-read({read,write})", duration);
    Ok(())
}

fn bench_echo_permissions(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/flags-test").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "echo-permissions").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::Flags(vec![])];

    for _ in 0..WARMUP_ITERATIONS {
        let args = [Val::Flags(vec!["read".into(), "execute".into()])];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        let args = [Val::Flags(vec!["read".into(), "execute".into()])];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("echo-permissions({read,execute})", duration);
    Ok(())
}

fn bench_sum_list(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/containers").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "sum-list").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::S32(0)];

    for _ in 0..WARMUP_ITERATIONS {
        let args = [Val::List(vec![Val::S32(1), Val::S32(2), Val::S32(3), Val::S32(4)])];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        let args = [Val::List(vec![Val::S32(1), Val::S32(2), Val::S32(3), Val::S32(4)])];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("sum-list([1,2,3,4])", duration);
    Ok(())
}

fn bench_count_list(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/containers").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "count-list").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::S32(0)];

    for _ in 0..WARMUP_ITERATIONS {
        let args = [Val::List(vec![
            Val::String("a".into()),
            Val::String("b".into()),
            Val::String("c".into()),
        ])];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        let args = [Val::List(vec![
            Val::String("a".into()),
            Val::String("b".into()),
            Val::String("c".into()),
        ])];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("count-list([\"a\",\"b\",\"c\"])", duration);
    Ok(())
}

fn bench_divide_ok(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/containers").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "divide").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::Result(Ok(None))];
    let args = [Val::S32(10), Val::S32(2)];

    for _ in 0..WARMUP_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("divide(10,2) -> Ok(5)", duration);
    Ok(())
}

fn bench_divide_err(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/containers").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "divide").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::Result(Ok(None))];
    let args = [Val::S32(10), Val::S32(0)];

    for _ in 0..WARMUP_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("divide(10,0) -> Err", duration);
    Ok(())
}

fn bench_add2(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/multi-params").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "add2").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::S32(0)];
    let args = [Val::S32(3), Val::S32(4)];

    for _ in 0..WARMUP_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("add2(3,4)", duration);
    Ok(())
}

fn bench_add4(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/multi-params").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "add4").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::S32(0)];
    let args = [Val::S32(1), Val::S32(2), Val::S32(3), Val::S32(4)];

    for _ in 0..WARMUP_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("add4(1,2,3,4)", duration);
    Ok(())
}

fn bench_concat3(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/multi-params").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "concat3").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::String("".into())];

    for _ in 0..WARMUP_ITERATIONS {
        let args = [
            Val::String("Hello".into()),
            Val::String(" ".into()),
            Val::String("World".into()),
        ];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        let args = [
            Val::String("Hello".into()),
            Val::String(" ".into()),
            Val::String("World".into()),
        ];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("concat3(\"Hello\",\" \",\"World\")", duration);
    Ok(())
}

fn bench_mixed_params(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/multi-params").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "mixed-params").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![Val::String("".into())];

    for _ in 0..WARMUP_ITERATIONS {
        let args = [Val::S32(42), Val::String("test".into()), Val::Bool(true)];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        let args = [Val::S32(42), Val::String("test".into()), Val::Bool(true)];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("mixed-params(42,\"test\",true)", duration);
    Ok(())
}

fn bench_no_return(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/side-effects").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "no-return").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![];

    for _ in 0..WARMUP_ITERATIONS {
        let args = [Val::String("msg".into())];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        let args = [Val::String("msg".into())];
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("no-return(\"msg\")", duration);
    Ok(())
}

fn bench_no_params_no_return(instance: &wasmtime::component::Instance, store: &mut Store<()>) -> Result<()> {
    let iface = instance.get_export(&mut *store, None, "local:types-test/side-effects").unwrap();
    let func_export = instance.get_export(&mut *store, Some(&iface), "no-params-no-return").unwrap();
    let func = instance.get_func(&mut *store, &func_export).unwrap();

    let mut results = vec![];
    let args: [Val; 0] = [];

    for _ in 0..WARMUP_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }

    let start = Instant::now();
    for _ in 0..BENCH_ITERATIONS {
        func.call(&mut *store, &args, &mut results)?;
        func.post_return(&mut *store)?;
    }
    let duration = start.elapsed();

    print_result("no-params-no-return()", duration);
    Ok(())
}
