// Tests for various WIT types

use anyhow::Result;
use wasmtime::component::{Component, Linker, Val};
use wasmtime::{Config, Engine, Store};
use wasmtime_wasi::{ResourceTable, WasiCtx, WasiCtxBuilder, WasiView};

struct HostState {
    wasi: WasiCtx,
    table: ResourceTable,
}

impl WasiView for HostState {
    fn ctx(&mut self) -> &mut WasiCtx {
        &mut self.wasi
    }

    fn table(&mut self) -> &mut ResourceTable {
        &mut self.table
    }
}

pub fn run_types_test(component_path: &str) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = Engine::new(&config)?;

    println!("Loading component: {}", component_path);
    let component = Component::from_file(&engine, component_path)?;

    let mut linker = Linker::<HostState>::new(&engine);
    wasmtime_wasi::add_to_linker_sync(&mut linker)?;

    let wasi = WasiCtxBuilder::new().build();
    let table = ResourceTable::new();
    let state = HostState { wasi, table };
    let mut store = Store::new(&engine, state);

    let instance = linker.instantiate(&mut store, &component)?;

    // Test primitives
    test_primitives(&instance, &mut store)?;

    // Test enums
    test_enums(&instance, &mut store)?;

    // Test flags
    test_flags(&instance, &mut store)?;

    // Test containers
    test_containers(&instance, &mut store)?;

    // Test multi-params
    test_multi_params(&instance, &mut store)?;

    // Test side-effects
    test_side_effects(&instance, &mut store)?;

    println!("\nAll types tests PASSED!");
    Ok(())
}

fn test_primitives(instance: &wasmtime::component::Instance, store: &mut Store<HostState>) -> Result<()> {
    println!("\n--- Testing primitives ---");

    let iface = instance
        .get_export(&mut *store, None, "local:types-test/primitives")
        .expect("primitives interface not found");

    // echo-s32
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "echo-s32")
            .expect("echo-s32 not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::S32(0)];
        func.call(&mut *store, &[Val::S32(42)], &mut results)?;
        assert_eq!(results[0], Val::S32(42));
        func.post_return(&mut *store)?;
        println!("  echo-s32(42) = 42 ✓");
    }

    // echo-s64
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "echo-s64")
            .expect("echo-s64 not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::S64(0)];
        func.call(&mut *store, &[Val::S64(9999999999i64)], &mut results)?;
        assert_eq!(results[0], Val::S64(9999999999i64));
        func.post_return(&mut *store)?;
        println!("  echo-s64(9999999999) = 9999999999 ✓");
    }

    // echo-f32
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "echo-f32")
            .expect("echo-f32 not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::Float32(0.0)];
        func.call(&mut *store, &[Val::Float32(3.14)], &mut results)?;
        if let Val::Float32(v) = results[0] {
            assert!((v - 3.14).abs() < 0.001);
        } else {
            panic!("unexpected result type");
        }
        func.post_return(&mut *store)?;
        println!("  echo-f32(3.14) ≈ 3.14 ✓");
    }

    // echo-bool
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "echo-bool")
            .expect("echo-bool not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::Bool(false)];
        func.call(&mut *store, &[Val::Bool(true)], &mut results)?;
        assert_eq!(results[0], Val::Bool(true));
        func.post_return(&mut *store)?;
        println!("  echo-bool(true) = true ✓");
    }

    // echo-string
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "echo-string")
            .expect("echo-string not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::String("".into())];
        func.call(&mut *store, &[Val::String("hello".into())], &mut results)?;
        let result_str = if let Val::String(s) = &results[0] {
            s.to_string()
        } else {
            panic!("unexpected result type");
        };
        assert_eq!(result_str, "hello");
        func.post_return(&mut *store)?;
        println!("  echo-string(\"hello\") = \"hello\" ✓");
    }

    Ok(())
}

fn test_enums(instance: &wasmtime::component::Instance, store: &mut Store<HostState>) -> Result<()> {
    println!("\n--- Testing enums ---");

    let iface = instance
        .get_export(&mut *store, None, "local:types-test/enums")
        .expect("enums interface not found");

    // echo-color (red=0, green=1, blue=2)
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "echo-color")
            .expect("echo-color not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();

        // Test Red (0)
        let mut results = vec![Val::Enum("".into())];
        func.call(&mut *store, &[Val::Enum("red".into())], &mut results)?;
        if let Val::Enum(s) = &results[0] {
            assert_eq!(s.as_str(), "red");
        } else {
            panic!("unexpected result type");
        }
        func.post_return(&mut *store)?;
        println!("  echo-color(red) = red ✓");

        // Test Green (1)
        func.call(&mut *store, &[Val::Enum("green".into())], &mut results)?;
        if let Val::Enum(s) = &results[0] {
            assert_eq!(s.as_str(), "green");
        } else {
            panic!("unexpected result type");
        }
        func.post_return(&mut *store)?;
        println!("  echo-color(green) = green ✓");
    }

    // color-name
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "color-name")
            .expect("color-name not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::String("".into())];
        func.call(&mut *store, &[Val::Enum("blue".into())], &mut results)?;
        let result_str = if let Val::String(s) = &results[0] {
            s.to_string()
        } else {
            panic!("unexpected result type");
        };
        assert_eq!(result_str, "blue");
        func.post_return(&mut *store)?;
        println!("  color-name(blue) = \"blue\" ✓");
    }

    Ok(())
}

fn test_flags(instance: &wasmtime::component::Instance, store: &mut Store<HostState>) -> Result<()> {
    println!("\n--- Testing flags ---");

    let iface = instance
        .get_export(&mut *store, None, "local:types-test/flags-test")
        .expect("flags-test interface not found");

    // has-read
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "has-read")
            .expect("has-read not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();

        // Flags value with just "read" bit set
        let flags_val = Val::Flags(vec!["read".into()]);
        let mut results = vec![Val::Bool(false)];
        func.call(&mut *store, &[flags_val], &mut results)?;
        assert_eq!(results[0], Val::Bool(true));
        func.post_return(&mut *store)?;
        println!("  has-read({{read}}) = true ✓");

        // Flags with no bits set
        let flags_val = Val::Flags(vec![]);
        func.call(&mut *store, &[flags_val], &mut results)?;
        assert_eq!(results[0], Val::Bool(false));
        func.post_return(&mut *store)?;
        println!("  has-read({{}}) = false ✓");
    }

    // has-write
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "has-write")
            .expect("has-write not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();

        // Flags with read and write
        let flags_val = Val::Flags(vec!["read".into(), "write".into()]);
        let mut results = vec![Val::Bool(false)];
        func.call(&mut *store, &[flags_val], &mut results)?;
        assert_eq!(results[0], Val::Bool(true));
        func.post_return(&mut *store)?;
        println!("  has-write({{read, write}}) = true ✓");
    }

    // echo-permissions
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "echo-permissions")
            .expect("echo-permissions not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();

        let flags_val = Val::Flags(vec!["read".into(), "execute".into()]);
        let mut results = vec![Val::Flags(vec![])];
        func.call(&mut *store, &[flags_val], &mut results)?;
        if let Val::Flags(flags) = &results[0] {
            assert!(flags.contains(&"read".into()));
            assert!(flags.contains(&"execute".into()));
            assert!(!flags.contains(&"write".into()));
        } else {
            panic!("unexpected result type");
        }
        func.post_return(&mut *store)?;
        println!("  echo-permissions({{read, execute}}) = {{read, execute}} ✓");
    }

    Ok(())
}

fn test_containers(instance: &wasmtime::component::Instance, store: &mut Store<HostState>) -> Result<()> {
    println!("\n--- Testing containers ---");

    let iface = instance
        .get_export(&mut *store, None, "local:types-test/containers")
        .expect("containers interface not found");

    // sum-list
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "sum-list")
            .expect("sum-list not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();

        let list_val = Val::List(vec![Val::S32(1), Val::S32(2), Val::S32(3), Val::S32(4)]);
        let mut results = vec![Val::S32(0)];
        func.call(&mut *store, &[list_val], &mut results)?;
        assert_eq!(results[0], Val::S32(10));
        func.post_return(&mut *store)?;
        println!("  sum-list([1,2,3,4]) = 10 ✓");
    }

    // count-list
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "count-list")
            .expect("count-list not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();

        let list_val = Val::List(vec![
            Val::String("a".into()),
            Val::String("b".into()),
            Val::String("c".into()),
        ]);
        let mut results = vec![Val::S32(0)];
        func.call(&mut *store, &[list_val], &mut results)?;
        assert_eq!(results[0], Val::S32(3));
        func.post_return(&mut *store)?;
        println!("  count-list([\"a\",\"b\",\"c\"]) = 3 ✓");
    }

    // divide (result type)
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "divide")
            .expect("divide not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();

        // Success case
        let mut results = vec![Val::Result(Ok(None))];
        func.call(&mut *store, &[Val::S32(10), Val::S32(2)], &mut results)?;
        if let Val::Result(Ok(Some(v))) = &results[0] {
            if let Val::S32(n) = **v {
                assert_eq!(n, 5);
            }
        } else {
            panic!("unexpected result: {:?}", results[0]);
        }
        func.post_return(&mut *store)?;
        println!("  divide(10, 2) = Ok(5) ✓");

        // Error case
        func.call(&mut *store, &[Val::S32(10), Val::S32(0)], &mut results)?;
        if let Val::Result(Err(Some(v))) = &results[0] {
            if let Val::String(s) = &**v {
                assert!(s.contains("zero"));
            }
        } else {
            panic!("unexpected result: {:?}", results[0]);
        }
        func.post_return(&mut *store)?;
        println!("  divide(10, 0) = Err(\"division by zero\") ✓");
    }

    Ok(())
}

fn test_multi_params(instance: &wasmtime::component::Instance, store: &mut Store<HostState>) -> Result<()> {
    println!("\n--- Testing multi-params ---");

    let iface = instance
        .get_export(&mut *store, None, "local:types-test/multi-params")
        .expect("multi-params interface not found");

    // add2
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "add2")
            .expect("add2 not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::S32(0)];
        func.call(&mut *store, &[Val::S32(3), Val::S32(4)], &mut results)?;
        assert_eq!(results[0], Val::S32(7));
        func.post_return(&mut *store)?;
        println!("  add2(3, 4) = 7 ✓");
    }

    // add3
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "add3")
            .expect("add3 not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::S32(0)];
        func.call(&mut *store, &[Val::S32(1), Val::S32(2), Val::S32(3)], &mut results)?;
        assert_eq!(results[0], Val::S32(6));
        func.post_return(&mut *store)?;
        println!("  add3(1, 2, 3) = 6 ✓");
    }

    // add4
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "add4")
            .expect("add4 not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::S32(0)];
        func.call(
            &mut *store,
            &[Val::S32(1), Val::S32(2), Val::S32(3), Val::S32(4)],
            &mut results,
        )?;
        assert_eq!(results[0], Val::S32(10));
        func.post_return(&mut *store)?;
        println!("  add4(1, 2, 3, 4) = 10 ✓");
    }

    // concat3
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "concat3")
            .expect("concat3 not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::String("".into())];
        func.call(
            &mut *store,
            &[
                Val::String("Hello".into()),
                Val::String(" ".into()),
                Val::String("World".into()),
            ],
            &mut results,
        )?;
        let result_str = if let Val::String(s) = &results[0] {
            s.to_string()
        } else {
            panic!("unexpected result type");
        };
        assert_eq!(result_str, "Hello World");
        func.post_return(&mut *store)?;
        println!("  concat3(\"Hello\", \" \", \"World\") = \"Hello World\" ✓");
    }

    // mixed-params
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "mixed-params")
            .expect("mixed-params not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![Val::String("".into())];
        func.call(
            &mut *store,
            &[Val::S32(42), Val::String("test".into()), Val::Bool(true)],
            &mut results,
        )?;
        let result_str = if let Val::String(s) = &results[0] {
            s.to_string()
        } else {
            panic!("unexpected result type");
        };
        assert_eq!(result_str, "42:test:true");
        func.post_return(&mut *store)?;
        println!("  mixed-params(42, \"test\", true) = \"42:test:true\" ✓");
    }

    Ok(())
}

fn test_side_effects(instance: &wasmtime::component::Instance, store: &mut Store<HostState>) -> Result<()> {
    println!("\n--- Testing side-effects ---");

    let iface = instance
        .get_export(&mut *store, None, "local:types-test/side-effects")
        .expect("side-effects interface not found");

    // no-return
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "no-return")
            .expect("no-return not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![];
        func.call(&mut *store, &[Val::String("test message".into())], &mut results)?;
        func.post_return(&mut *store)?;
        println!("  no-return(\"test message\") completed ✓");
    }

    // no-params-no-return
    {
        let func_export = instance
            .get_export(&mut *store, Some(&iface), "no-params-no-return")
            .expect("no-params-no-return not found");
        let func = instance.get_func(&mut *store, &func_export).unwrap();
        let mut results = vec![];
        func.call(&mut *store, &[], &mut results)?;
        func.post_return(&mut *store)?;
        println!("  no-params-no-return() completed ✓");
    }

    Ok(())
}
