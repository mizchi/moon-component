///|
test "targets hello component" {
  let component_path = "examples/hello/hello.component.wasm"
  let wit_path = "examples/hello/wit"
  let bytes = @fs.read_file_to_bytes(component_path) catch {
    _ => {
      inspect("skip", content="skip")
      return
    }
  }
  let resolved = match @wit.resolve_path(wit_path) {
    Ok(v) => v
    Err(_) => {
      inspect("skip", content="skip")
      return
    }
  }
  let result = check_component_targets(bytes, resolved)
  match result {
    Ok(_) => inspect("ok", content="ok")
    Err(e) => inspect("error: " + e, content="error: ")
  }
}
