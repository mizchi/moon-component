///|
test "extract method from wagi env lines" {
  let lines = [
    "PATH_INFO=/users/42", "REQUEST_METHOD=POST", "QUERY_STRING=id=42",
  ]
  inspect(method_from_environment_lines(lines), content="POST")
}

///|
test "fallback method is GET when missing" {
  inspect(method_from_environment_lines(["PATH_INFO=/"]), content="GET")
}

///|
test "env method flag detection" {
  inspect(should_use_environment_method(["/users/42", ""]), content="false")
  inspect(
    should_use_environment_method(["/users/42", "--use-env-method"]),
    content="true",
  )
}
