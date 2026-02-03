///|
test "parse wac example" {
  let path = "examples/wac/script.wac"
  let source = @fs.read_file_to_string(path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let doc = match parse_wac(source) {
    Ok(v) => v
    Err(e) => {
      inspect("error: " + e.to_string(), content="error: ")
      return
    }
  }
  assert_eq(doc.pkg, "example:composition")
  assert_true(doc.stmts.length() > 0)
}

///|
test "compose wac example" {
  let path = "examples/wac/script.wac"
  let composed = match compose_wac_file(path) {
    Ok(bytes) => bytes
    Err(e) => {
      inspect("error: " + e, content="error: ")
      return
    }
  }
  let composed_info = match parse_component_info(composed) {
    Ok(v) => v
    Err(e) => {
      inspect("parse error: " + e.to_string(), content="parse error: ")
      return
    }
  }
  let greeter_path = "examples/wac/deps/example/greeter.wasm"
  let greeter_bytes = @fs.read_file_to_bytes(greeter_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let greeter_info = match parse_component_info(greeter_bytes) {
    Ok(v) => v
    Err(e) => {
      inspect("parse error: " + e.to_string(), content="parse error: ")
      return
    }
  }
  assert_eq(composed_info.imports.length(), 0)
  assert_eq(composed_info.exports.length(), greeter_info.exports.length())
}

///|
test "parse wac import alias and named access" {
  let source =
    #|package example:composition targets wasi:http/proxy;
    #|import greeter as "g": example:greeter/greeter;
    #|let app = new example:app { greeter };
    #|export app["wasi:io/outgoing-stream"];
    #|
  let doc = match parse_wac(source) {
    Ok(v) => v
    Err(e) => {
      inspect("error: " + e.to_string(), content="error: ")
      return
    }
  }
  guard doc.targets is Some("wasi:http/proxy") else { fail("missing targets") }
  assert_eq(doc.stmts.length(), 3)
  match doc.stmts[0] {
    WacStmt::Import(imp) => {
      assert_eq(imp.local_name, "greeter")
      assert_eq(imp.import_name, "g")
      match imp.ty {
        WacImportType::Package(pkg) => assert_eq(pkg, "example:greeter/greeter")
        _ => fail("expected package import type")
      }
    }
    _ => fail("expected import stmt")
  }
  match doc.stmts[2] {
    WacStmt::Export(exp) =>
      match exp.expr {
        WacExpr::Access(_, name) => {
          assert_true(name.exact)
          assert_eq(name.value, "wasi:io/outgoing-stream")
        }
        _ => fail("expected access expr")
      }
    _ => fail("expected export stmt")
  }
}

///|
test "parse wac let with named access and spreads" {
  let source =
    #|package foo:bar;
    #|let x = new foo:bar { foo, ...i, "bar": (new baz:qux { ... }), "baz": foo["baz"].qux, ... };
    #|
  let doc = match parse_wac(source) {
    Ok(v) => v
    Err(e) => {
      inspect("error: " + e.to_string(), content="error: ")
      return
    }
  }
  assert_eq(doc.stmts.length(), 1)
  match doc.stmts[0] {
    WacStmt::Let(_, expr) =>
      match expr {
        WacExpr::New(new_expr) => {
          assert_eq(new_expr.args.length(), 5)
          match new_expr.args[0] {
            WacArg::Inferred(_) => ()
            _ => fail("expected inferred arg")
          }
          match new_expr.args[1] {
            WacArg::SpreadInstance(name) => assert_eq(name, "i")
            _ => fail("expected spread instance")
          }
          match new_expr.args[2] {
            WacArg::Named(name, _) => {
              assert_true(name.exact)
              assert_eq(name.value, "bar")
            }
            _ => fail("expected named arg")
          }
          match new_expr.args[3] {
            WacArg::Named(name, _) => {
              assert_true(name.exact)
              assert_eq(name.value, "baz")
            }
            _ => fail("expected named arg")
          }
          match new_expr.args[4] {
            WacArg::SpreadAll => ()
            _ => fail("expected spread all")
          }
        }
        _ => fail("expected new expr")
      }
    _ => fail("expected let stmt")
  }
}

///|
test "parse wac export as and spread" {
  let source =
    #|package foo:bar;
    #|let i = new foo:bar {};
    #|export i["x"] as "y";
    #|export i...;
    #|
  let doc = match parse_wac(source) {
    Ok(v) => v
    Err(e) => {
      inspect("error: " + e.to_string(), content="error: ")
      return
    }
  }
  assert_eq(doc.stmts.length(), 3)
  match doc.stmts[1] {
    WacStmt::Export(exp) => {
      guard exp.as_name is Some("y") else { fail("missing export alias") }
      match exp.expr {
        WacExpr::Access(_, name) => {
          assert_true(name.exact)
          assert_eq(name.value, "x")
        }
        _ => fail("expected access expr")
      }
    }
    _ => fail("expected export stmt")
  }
  match doc.stmts[2] {
    WacStmt::Export(exp) => assert_true(exp.all)
    _ => fail("expected export stmt")
  }
}

///|
test "parse wac inline import types" {
  let source =
    #|package foo:bar;
    #|import greeter: interface { greet: func() -> string; };
    #|
  let doc = match parse_wac(source) {
    Ok(v) => v
    Err(e) => {
      inspect("error: " + e.to_string(), content="error: ")
      return
    }
  }
  match doc.stmts[0] {
    WacStmt::Import(imp) =>
      match imp.ty {
        WacImportType::InlineInterface(_) => ()
        _ => fail("expected inline interface import")
      }
    _ => fail("expected import stmt")
  }
}

///|
test "compose wac dce removes unused instance" {
  let base_dir = "examples/wac"
  let hello_path = base_dir + "/deps/example/hello.wasm"
  let greeter_path = base_dir + "/deps/example/greeter.wasm"
  let _ = @fs.read_file_to_bytes(hello_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let _ = @fs.read_file_to_bytes(greeter_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let source =
    #|package example:composition;
    #|let unused = new example:hello {};
    #|let hello = new example:hello {};
    #|let greeter = new example:greeter { hello: hello.hello };
    #|export greeter.greet;
    #|
  let bytes_no = match compose_wac_source(source, base_dir) {
    Ok(v) => v
    Err(e) => {
      inspect("error: " + e, content="error: ")
      return
    }
  }
  let bytes_dce = match compose_wac_source(source, base_dir, dce=true) {
    Ok(v) => v
    Err(e) => {
      inspect("error: " + e, content="error: ")
      return
    }
  }
  let detail_no = match parse_component_detail(bytes_no) {
    Ok(v) => v
    Err(e) => {
      inspect("parse error: " + e.to_string(), content="parse error: ")
      return
    }
  }
  let detail_dce = match parse_component_detail(bytes_dce) {
    Ok(v) => v
    Err(e) => {
      inspect("parse error: " + e.to_string(), content="parse error: ")
      return
    }
  }
  assert_true(detail_dce.instances.length() < detail_no.instances.length())
  assert_eq(detail_no.instances.length() - 1, detail_dce.instances.length())
}

///|
test "compose wac spread instance mismatch" {
  let base_dir = "examples/wac"
  let hello_path = base_dir + "/deps/example/hello.wasm"
  let _ = @fs.read_file_to_bytes(hello_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let source =
    #|package example:composition;
    #|let hello = new example:hello {};
    #|let app = new example:hello { ...hello };
    #|export hello.hello;
    #|
  let result = compose_wac_source(source, base_dir)
  match result {
    Ok(_) => fail("expected spread mismatch")
    Err(e) => assert_true(e.contains("spread instance"))
  }
}
