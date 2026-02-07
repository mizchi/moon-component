///|
test "TrieRouter static and param" {
  let router = TrieRouter::new()
  let _ = router.add(@router.Method::Get, "/")
  let _ = router.add(@router.Method::Get, "/users/:id")
  let top = router.match_(@router.Method::Get, "/")
  assert_eq(top.handlers.length(), 1)
  let user = router.match_(@router.Method::Get, "/users/100")
  assert_eq(user.handlers.length(), 1)
  let (_, params) = user.handlers[0]
  inspect(params.get("id"), content="Some(\"100\")")
}

///|
test "TrieRouter wildcard" {
  let router = TrieRouter::new()
  let _ = router.add(@router.Method::Get, "/files/*")
  let m = router.match_(@router.Method::Get, "/files/a/b/c")
  assert_eq(m.handlers.length(), 1)
}

///|
test "TrieRouter optional parameter" {
  let router = TrieRouter::new()
  let _ = router.add(@router.Method::Get, "/api/animals/:type?")
  let m1 = router.match_(@router.Method::Get, "/api/animals")
  assert_eq(m1.handlers.length(), 1)
  let m2 = router.match_(@router.Method::Get, "/api/animals/dog")
  assert_eq(m2.handlers.length(), 1)
}
