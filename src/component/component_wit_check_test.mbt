///|
fn resolve_wit(path : String) -> @wit.ResolveInput? {
  match @wit.resolve_path(path) {
    Ok(v) => Some(v)
    Err(_) => None
  }
}

///|
test "wit check compose example" {
  let socket_wit = "examples/compose/apps/main/component/wit"
  let math_wit = "examples/compose/libs/math/component/wit"
  let strings_wit = "examples/compose/libs/strings/component/wit"
  let socket_res = resolve_wit(socket_wit)
  let math_res = resolve_wit(math_wit)
  let strings_res = resolve_wit(strings_wit)
  match (socket_res, math_res, strings_res) {
    (Some(socket), Some(math), Some(strings)) => {
      let result = check_plug_wit(socket, [math, strings])
      match result {
        Ok(_) => inspect("ok", content="ok")
        Err(msg) => inspect("error: " + msg, content="error: ")
      }
    }
    _ => inspect("skip", content="skip")
  }
}
