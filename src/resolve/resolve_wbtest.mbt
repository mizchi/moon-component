///|
/// Test Type FromJson for primitives
test "type_from_json_primitives" {
  let bool_json = @json.parse("\"bool\"") catch { _ => panic() }
  let ty : Type = @json.from_json(bool_json) catch { _ => panic() }
  inspect(ty, content="Bool")
  let u8_json = @json.parse("\"u8\"") catch { _ => panic() }
  let ty2 : Type = @json.from_json(u8_json) catch { _ => panic() }
  inspect(ty2, content="U8")
  let s32_json = @json.parse("\"s32\"") catch { _ => panic() }
  let ty3 : Type = @json.from_json(s32_json) catch { _ => panic() }
  inspect(ty3, content="S32")
  let string_json = @json.parse("\"string\"") catch { _ => panic() }
  let ty4 : Type = @json.from_json(string_json) catch { _ => panic() }
  inspect(ty4, content="String_")
}

///|
/// Test Type FromJson for Id reference
test "type_from_json_id" {
  let id_json = @json.parse("42") catch { _ => panic() }
  let ty : Type = @json.from_json(id_json) catch { _ => panic() }
  inspect(ty, content="Id(42)")
}

///|
/// Test RecordField FromJson
test "record_field_from_json" {
  let json = @json.parse("{\"name\": \"x\", \"type\": \"s32\"}") catch {
    _ => panic()
  }
  let field : RecordField = @json.from_json(json) catch { _ => panic() }
  inspect(field.name, content="x")
  inspect(field.field_type, content="S32")
}

///|
/// Test VariantCase FromJson with type
test "variant_case_from_json_with_type" {
  let json = @json.parse("{\"name\": \"circle\", \"type\": \"s32\"}") catch {
    _ => panic()
  }
  let case : VariantCase = @json.from_json(json) catch { _ => panic() }
  inspect(case.name, content="circle")
  inspect(case.case_type, content="Some(S32)")
}

///|
/// Test VariantCase FromJson without type
test "variant_case_from_json_without_type" {
  let json = @json.parse("{\"name\": \"none\", \"type\": null}") catch {
    _ => panic()
  }
  let case : VariantCase = @json.from_json(json) catch { _ => panic() }
  inspect(case.name, content="none")
  inspect(case.case_type, content="None")
}

///|
/// Test TypeKind FromJson for record
test "type_kind_from_json_record" {
  let json_str =
    #|{"record": {"fields": [{"name": "x", "type": "s32"}, {"name": "y", "type": "s32"}]}}
  let json = @json.parse(json_str) catch { _ => panic() }
  let kind : TypeKind = @json.from_json(json) catch { _ => panic() }
  match kind {
    Record(fields) => {
      inspect(fields.length(), content="2")
      inspect(fields[0].name, content="x")
      inspect(fields[1].name, content="y")
    }
    _ => panic()
  }
}

///|
/// Test TypeKind FromJson for variant
test "type_kind_from_json_variant" {
  let json_str =
    #|{"variant": {"cases": [{"name": "a", "type": "s32"}, {"name": "b", "type": null}]}}
  let json = @json.parse(json_str) catch { _ => panic() }
  let kind : TypeKind = @json.from_json(json) catch { _ => panic() }
  match kind {
    Variant(cases) => {
      inspect(cases.length(), content="2")
      inspect(cases[0].name, content="a")
      inspect(cases[0].case_type, content="Some(S32)")
      inspect(cases[1].name, content="b")
      inspect(cases[1].case_type, content="None")
    }
    _ => panic()
  }
}

///|
/// Test TypeKind FromJson for list
test "type_kind_from_json_list" {
  let json = @json.parse("{\"list\": \"s32\"}") catch { _ => panic() }
  let kind : TypeKind = @json.from_json(json) catch { _ => panic() }
  match kind {
    List(inner) => inspect(inner, content="S32")
    _ => panic()
  }
}

///|
/// Test TypeKind FromJson for option
test "type_kind_from_json_option" {
  let json = @json.parse("{\"option\": \"string\"}") catch { _ => panic() }
  let kind : TypeKind = @json.from_json(json) catch { _ => panic() }
  match kind {
    Option(inner) => inspect(inner, content="String_")
    _ => panic()
  }
}

///|
/// Test TypeKind FromJson for result
test "type_kind_from_json_result" {
  let json = @json.parse("{\"result\": {\"ok\": \"s32\", \"err\": \"string\"}}") catch {
    _ => panic()
  }
  let kind : TypeKind = @json.from_json(json) catch { _ => panic() }
  match kind {
    Result(ok~, err~) => {
      inspect(ok, content="Some(S32)")
      inspect(err, content="Some(String_)")
    }
    _ => panic()
  }
}

///|
/// Test TypeOwner FromJson
test "type_owner_from_json" {
  let iface_json = @json.parse("{\"interface\": 0}") catch { _ => panic() }
  let owner : TypeOwner = @json.from_json(iface_json) catch { _ => panic() }
  inspect(owner, content="Interface(0)")
  let world_json = @json.parse("{\"world\": 1}") catch { _ => panic() }
  let owner2 : TypeOwner = @json.from_json(world_json) catch { _ => panic() }
  inspect(owner2, content="World(1)")
  let none_json = @json.parse("null") catch { _ => panic() }
  let owner3 : TypeOwner = @json.from_json(none_json) catch { _ => panic() }
  inspect(owner3, content="None")
}

///|
/// Test Function FromJson
test "function_from_json" {
  let json_str =
    #|{"kind": "freestanding", "name": "add", "params": [{"name": "a", "type": "s32"}, {"name": "b", "type": "s32"}], "result": "s32"}
  let json = @json.parse(json_str) catch { _ => panic() }
  let func : Function = @json.from_json(json) catch { _ => panic() }
  inspect(func.name, content="add")
  inspect(func.params.length(), content="2")
  inspect(func.params[0].0, content="a")
  inspect(func.params[1].0, content="b")
  inspect(func.result, content="Some(S32)")
}

///|
/// Test Function FromJson without result
test "function_from_json_no_result" {
  let json_str =
    #|{"kind": "freestanding", "name": "log", "params": [{"name": "msg", "type": "string"}], "result": null}
  let json = @json.parse(json_str) catch { _ => panic() }
  let func : Function = @json.from_json(json) catch { _ => panic() }
  inspect(func.name, content="log")
  inspect(func.result, content="None")
}

///|
/// Test WorldItem FromJson for type entries
test "world_item_from_json_type" {
  let json = @json.parse("{\"type\": 3}") catch { _ => panic() }
  let item : WorldItem = @json.from_json(json) catch { _ => panic() }
  inspect(item, content="Type(3)")
}
