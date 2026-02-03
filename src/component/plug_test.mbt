///|
fn has_export(
  exports : Array[ExportInfo],
  name : Bytes,
  kind : ExternKind,
) -> Bool {
  for e in exports {
    if e.kind == kind && e.name == name {
      return true
    }
  }
  false
}

///|
test "plug compose example" {
  let socket_path = "examples/compose/_build/bundle/entry.wasm"
  let math_path = "examples/compose/_build/bundle/deps/example/math.wasm"
  let strings_path = "examples/compose/_build/bundle/deps/example/strings.wasm"
  let socket_bytes = @fs.read_file_to_bytes(socket_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let math_bytes = @fs.read_file_to_bytes(math_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let strings_bytes = @fs.read_file_to_bytes(strings_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let result = plug_components(socket_bytes, [math_bytes, strings_bytes])
  let composed = match result {
    Ok(bytes) => bytes
    Err(e) => {
      inspect("error: " + e.to_string(), content="error: ")
      return
    }
  }
  let socket_info = match parse_component_info(socket_bytes) {
    Ok(v) => v
    Err(e) => {
      inspect("parse error: " + e.to_string(), content="parse error: ")
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
  assert_eq(composed_info.imports.length(), 0)
  assert_eq(composed_info.exports.length(), socket_info.exports.length())
  for e in socket_info.exports {
    assert_true(has_export(composed_info.exports, e.name, e.kind))
  }
}

///|
test "plug core module import" {
  let socket_path = "examples/core-module/socket.wasm"
  let plug_path = "examples/core-module/plug.wasm"
  let socket_bytes = @fs.read_file_to_bytes(socket_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let plug_bytes = @fs.read_file_to_bytes(plug_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let result = plug_components(socket_bytes, [plug_bytes])
  let composed = match result {
    Ok(bytes) => bytes
    Err(e) => {
      inspect("error: " + e.to_string(), content="error: ")
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
  assert_eq(composed_info.imports.length(), 0)
  assert_eq(composed_info.exports.length(), 0)
}

///|
test "plug wac example" {
  let socket_path = "examples/wac/deps/example/greeter.wasm"
  let plug_path = "examples/wac/deps/example/hello.wasm"
  let socket_bytes = @fs.read_file_to_bytes(socket_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let plug_bytes = @fs.read_file_to_bytes(plug_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let result = plug_components(socket_bytes, [plug_bytes])
  let composed = match result {
    Ok(bytes) => bytes
    Err(e) => {
      inspect("error: " + e.to_string(), content="error: ")
      return
    }
  }
  let socket_info = match parse_component_info(socket_bytes) {
    Ok(v) => v
    Err(e) => {
      inspect("parse error: " + e.to_string(), content="parse error: ")
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
  assert_eq(composed_info.imports.length(), 0)
  assert_eq(composed_info.exports.length(), socket_info.exports.length())
  for e in socket_info.exports {
    assert_true(has_export(composed_info.exports, e.name, e.kind))
  }
}
