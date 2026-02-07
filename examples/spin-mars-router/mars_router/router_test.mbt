///|
test "Method::from_string" {
  inspect(Method::from_string("GET"), content="Some(GET)")
  inspect(Method::from_string("INVALID"), content="None")
}

///|
test "Params basic operations" {
  let params = Params::new()
  assert_true(params.is_empty())
  params.set("id", "123")
  inspect(params.get("id"), content="Some(\"123\")")
}
