/// WIT Resolve types for MoonBit code generation

///|
/// Type reference
pub(all) enum Type {
  Bool
  U8
  U16
  U32
  U64
  S8
  S16
  S32
  S64
  F32
  F64
  Char
  String_
  Id(Int)
} derive(Show, Eq, ToJson)

// Custom FromJson for Type to handle lowercase strings like "u32"

///|
pub impl @json.FromJson for Type with from_json(json, path) {
  match json {
    String(s) =>
      match s {
        "bool" => Bool
        "u8" => U8
        "u16" => U16
        "u32" => U32
        "u64" => U64
        "s8" => S8
        "s16" => S16
        "s32" => S32
        "s64" => S64
        "f32" => F32
        "f64" => F64
        "char" => Char
        "string" => String_
        _ => raise @json.JsonDecodeError((path, "Type: unknown type " + s))
      }
    Object(obj) =>
      // Handle {"id": 123} format for type references
      match obj.get("id") {
        Some(Number(n, ..)) => Id(n.to_int())
        _ => raise @json.JsonDecodeError((path, "Type: expected id field"))
      }
    Number(n, ..) => Id(n.to_int())
    _ => raise @json.JsonDecodeError((path, "Type: expected string or object"))
  }
}

///|
/// Function result
pub(all) enum FunctionResult {
  Named(Array[(String, Type)])
  Anon(Type)
} derive(Show, Eq, FromJson, ToJson)

///|
/// Function kind
pub(all) enum FunctionKind {
  Freestanding
  Constructor(Int) // type_id of the resource
  Method(Int) // type_id of the resource
  Static(Int) // type_id of the resource
} derive(Show, Eq, ToJson)

// Custom FromJson for FunctionKind to handle lowercase strings and objects

///|
pub impl @json.FromJson for FunctionKind with from_json(json, path) {
  match json {
    String(s) =>
      match s {
        "freestanding" => Freestanding
        _ =>
          raise @json.JsonDecodeError((path, "FunctionKind: unknown kind " + s))
      }
    Object(obj) => {
      // Check for constructor
      match obj.get("constructor") {
        Some(Number(n, ..)) => return Constructor(n.to_int())
        _ => ()
      }
      // Check for method
      match obj.get("method") {
        Some(Number(n, ..)) => return Method(n.to_int())
        _ => ()
      }
      // Check for static
      match obj.get("static") {
        Some(Number(n, ..)) => return Static(n.to_int())
        _ => ()
      }
      raise @json.JsonDecodeError((path, "FunctionKind: unknown object kind"))
    }
    _ =>
      raise @json.JsonDecodeError(
        (path, "FunctionKind: expected string or object"),
      )
  }
}

///|
/// Function definition
pub(all) struct Function {
  name : String
  kind : FunctionKind
  params : Array[(String, Type)]
  result : Type?
} derive(Show, Eq, ToJson)

// Custom FromJson for Function to handle params format

///|
pub impl @json.FromJson for Function with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "Function: expected object"))
  }
  let name = match obj.get("name") {
    Some(String(s)) => s
    _ => raise @json.JsonDecodeError((path, "Function: missing name"))
  }
  let kind : FunctionKind = match obj.get("kind") {
    Some(k) => @json.from_json(k, path=path.add_key("kind"))
    _ => Freestanding
  }
  // Parse params: [{"name": "a", "type": "u32"}, ...]
  let params : Array[(String, Type)] = match obj.get("params") {
    Some(Array(arr)) => {
      let result : Array[(String, Type)] = []
      for i, item in arr {
        guard item is Object(param_obj) else {
          raise @json.JsonDecodeError(
            (path, "Function: param should be object"),
          )
        }
        let pname = match param_obj.get("name") {
          Some(String(s)) => s
          _ =>
            raise @json.JsonDecodeError((path, "Function: param missing name"))
        }
        let ptype : Type = match param_obj.get("type") {
          Some(t) =>
            @json.from_json(
              t,
              path=path.add_key("params").add_index(i).add_key("type"),
            )
          _ =>
            raise @json.JsonDecodeError((path, "Function: param missing type"))
        }
        result.push((pname, ptype))
      }
      result
    }
    _ => []
  }
  let result : Type? = match obj.get("result") {
    Some(Null) | None => None
    Some(r) => Some(@json.from_json(r, path=path.add_key("result")))
  }
  { name, kind, params, result }
}

///|
/// World item
pub(all) enum WorldItem {
  Interface(InterfaceRef)
  Function(Function)
} derive(Show, Eq, ToJson)

// Custom FromJson for WorldItem to handle lowercase keys

///|
pub impl @json.FromJson for WorldItem with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "WorldItem: expected object"))
  }
  match obj.get("interface") {
    Some(iface) => {
      let iref : InterfaceRef = @json.from_json(
        iface,
        path=path.add_key("interface"),
      )
      Interface(iref)
    }
    None =>
      match obj.get("function") {
        Some(func) => {
          let f : Function = @json.from_json(
            func,
            path=path.add_key("function"),
          )
          Function(f)
        }
        None =>
          raise @json.JsonDecodeError(
            (path, "WorldItem: expected interface or function"),
          )
      }
  }
}

///|
pub(all) struct InterfaceRef {
  id : Int
} derive(Show, Eq, FromJson, ToJson)

///|
/// Interface definition
pub(all) struct Interface {
  name : String?
  functions : Map[String, Function]
  types : Map[String, Int]
  pkg : Int?
} derive(Show, Eq, ToJson)

// Custom FromJson for Interface to handle package field name

///|
pub impl @json.FromJson for Interface with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "Interface: expected object"))
  }
  let name : String? = match obj.get("name") {
    Some(String(s)) => Some(s)
    Some(Null) | None => None
    _ => raise @json.JsonDecodeError((path, "Interface: name should be string"))
  }
  let functions : Map[String, Function] = match obj.get("functions") {
    Some(f) => @json.from_json(f, path=path.add_key("functions"))
    None => {}
  }
  let types : Map[String, Int] = match obj.get("types") {
    Some(t) => @json.from_json(t, path=path.add_key("types"))
    None => {}
  }
  // Handle both "pkg" and "package" field names
  let pkg : Int? = match obj.get("package") {
    Some(Number(n, ..)) => Some(n.to_int())
    Some(Null) | None =>
      match obj.get("pkg") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
    _ => None
  }
  { name, functions, types, pkg }
}

///|
/// World definition
pub(all) struct World {
  name : String
  imports : Map[String, WorldItem]
  exports : Map[String, WorldItem]
  pkg : Int?
} derive(Show, Eq, ToJson)

// Custom FromJson for World to handle package field name

///|
pub impl @json.FromJson for World with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "World: expected object"))
  }
  let name = match obj.get("name") {
    Some(String(s)) => s
    _ => raise @json.JsonDecodeError((path, "World: missing name"))
  }
  let imports : Map[String, WorldItem] = match obj.get("imports") {
    Some(i) => @json.from_json(i, path=path.add_key("imports"))
    None => {}
  }
  let exports : Map[String, WorldItem] = match obj.get("exports") {
    Some(e) => @json.from_json(e, path=path.add_key("exports"))
    None => {}
  }
  // Handle both "pkg" and "package" field names
  let pkg : Int? = match obj.get("package") {
    Some(Number(n, ..)) => Some(n.to_int())
    Some(Null) | None =>
      match obj.get("pkg") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
    _ => None
  }
  { name, imports, exports, pkg }
}

///|
/// Package name
pub(all) struct PackageName {
  ns : String // namespace field renamed
  name : String
  version : String?
} derive(Show, Eq, ToJson)

// Custom FromJson for PackageName to handle "my:calc" format

///|
pub impl @json.FromJson for PackageName with from_json(json, path) {
  match json {
    String(s) => {
      // Parse "namespace:name" or "namespace:name@version"
      let parts : Array[String] = s
        .split(":")
        .map(fn(sv) { sv.to_string() })
        .collect()
      if parts.length() >= 2 {
        let ns = parts[0]
        let rest = parts[1]
        let name_ver : Array[String] = rest
          .split("@")
          .map(fn(sv) { sv.to_string() })
          .collect()
        let name = name_ver[0]
        let version : String? = if name_ver.length() > 1 {
          Some(name_ver[1])
        } else {
          None
        }
        { ns, name, version }
      } else {
        { ns: "", name: s, version: None }
      }
    }
    Object(obj) => {
      let ns = match obj.get("namespace") {
        Some(String(s)) => s
        _ => ""
      }
      let name = match obj.get("name") {
        Some(String(s)) => s
        _ => ""
      }
      let version : String? = match obj.get("version") {
        Some(String(s)) => Some(s)
        _ => None
      }
      { ns, name, version }
    }
    _ => {
      let msg = "PackageName: expected string or object"
      raise @json.JsonDecodeError((path, msg))
    }
  }
}

///|
/// Package definition
pub(all) struct Package {
  name : PackageName
  interfaces : Map[String, Int]
  worlds : Map[String, Int]
} derive(Show, Eq, FromJson, ToJson)

///|
/// Type definition owner
pub(all) enum TypeOwner {
  Interface(Int)
  World(Int)
  None
} derive(Show, Eq, ToJson)

///|
pub impl @json.FromJson for TypeOwner with from_json(json, _path) {
  match json {
    Null => None
    Object(obj) =>
      match obj.get("interface") {
        Some(Number(n, ..)) => Interface(n.to_int())
        _ =>
          match obj.get("world") {
            Some(Number(n, ..)) => World(n.to_int())
            _ => None
          }
      }
    _ => None
  }
}

///|
/// Record field
pub(all) struct RecordField {
  name : String
  field_type : Type
} derive(Show, Eq, ToJson)

///|
pub impl @json.FromJson for RecordField with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "RecordField: expected object"))
  }
  let name = match obj.get("name") {
    Some(String(s)) => s
    _ => raise @json.JsonDecodeError((path, "RecordField: missing name"))
  }
  let field_type : Type = match obj.get("type") {
    Some(t) => @json.from_json(t, path=path.add_key("type"))
    _ => raise @json.JsonDecodeError((path, "RecordField: missing type"))
  }
  { name, field_type }
}

///|
/// Variant case
pub(all) struct VariantCase {
  name : String
  case_type : Type?
} derive(Show, Eq, ToJson)

///|
pub impl @json.FromJson for VariantCase with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "VariantCase: expected object"))
  }
  let name = match obj.get("name") {
    Some(String(s)) => s
    _ => raise @json.JsonDecodeError((path, "VariantCase: missing name"))
  }
  let case_type : Type? = match obj.get("type") {
    Some(Null) | None => None
    Some(t) => Some(@json.from_json(t, path=path.add_key("type")))
  }
  { name, case_type }
}

///|
/// Handle kind for resource references
pub(all) enum HandleKind {
  Own(Int) // type_id of the resource
  Borrow(Int) // type_id of the resource
} derive(Show, Eq, ToJson)

///|
pub impl @json.FromJson for HandleKind with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "HandleKind: expected object"))
  }
  match obj.get("own") {
    Some(Number(n, ..)) => return Own(n.to_int())
    _ => ()
  }
  match obj.get("borrow") {
    Some(Number(n, ..)) => return Borrow(n.to_int())
    _ => ()
  }
  raise @json.JsonDecodeError((path, "HandleKind: unknown handle kind"))
}

///|
/// Type kind
pub(all) enum TypeKind {
  Record(Array[RecordField])
  Variant(Array[VariantCase])
  List(Type)
  Option(Type)
  Result(ok~ : Type?, err~ : Type?)
  Tuple(Array[Type])
  Flags(Array[String])
  Enum(Array[String])
  Alias(Type)
  Resource // opaque resource type
  Handle(HandleKind) // own<T> or borrow<T>
} derive(Show, Eq, ToJson)

///|
pub impl @json.FromJson for TypeKind with from_json(json, path) {
  // Handle string kinds (like "resource")
  match json {
    String(s) =>
      match s {
        "resource" => return Resource
        _ =>
          raise @json.JsonDecodeError(
            (path, "TypeKind: unknown string kind " + s),
          )
      }
    _ => ()
  }
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "TypeKind: expected object or string"))
  }
  // Check each possible kind
  match obj.get("record") {
    Some(Object(rec)) =>
      match rec.get("fields") {
        Some(Array(fields)) => {
          let parsed : Array[RecordField] = []
          for i, f in fields {
            parsed.push(
              @json.from_json(
                f,
                path=path.add_key("record").add_key("fields").add_index(i),
              ),
            )
          }
          return Record(parsed)
        }
        _ => ()
      }
    _ => ()
  }
  match obj.get("variant") {
    Some(Object(variant_obj)) =>
      match variant_obj.get("cases") {
        Some(Array(cases)) => {
          let parsed : Array[VariantCase] = []
          for i, c in cases {
            parsed.push(
              @json.from_json(
                c,
                path=path.add_key("variant").add_key("cases").add_index(i),
              ),
            )
          }
          return Variant(parsed)
        }
        _ => ()
      }
    _ => ()
  }
  match obj.get("list") {
    Some(t) => return List(@json.from_json(t, path=path.add_key("list")))
    _ => ()
  }
  match obj.get("option") {
    Some(t) => return Option(@json.from_json(t, path=path.add_key("option")))
    _ => ()
  }
  match obj.get("result") {
    Some(Object(res)) => {
      let ok : Type? = match res.get("ok") {
        Some(Null) | None => None
        Some(t) =>
          Some(@json.from_json(t, path=path.add_key("result").add_key("ok")))
      }
      let err : Type? = match res.get("err") {
        Some(Null) | None => None
        Some(t) =>
          Some(@json.from_json(t, path=path.add_key("result").add_key("err")))
      }
      return Result(ok~, err~)
    }
    _ => ()
  }
  match obj.get("tuple") {
    Some(Object(tup)) =>
      match tup.get("types") {
        Some(Array(types)) => {
          let parsed : Array[Type] = []
          for i, t in types {
            parsed.push(
              @json.from_json(
                t,
                path=path.add_key("tuple").add_key("types").add_index(i),
              ),
            )
          }
          return Tuple(parsed)
        }
        _ => ()
      }
    _ => ()
  }
  match obj.get("flags") {
    Some(Object(fl)) =>
      match fl.get("flags") {
        Some(Array(flags)) => {
          let parsed : Array[String] = []
          for f in flags {
            guard f is Object(fobj) else { continue }
            match fobj.get("name") {
              Some(String(s)) => parsed.push(s)
              _ => ()
            }
          }
          return Flags(parsed)
        }
        _ => ()
      }
    _ => ()
  }
  match obj.get("enum") {
    Some(Object(en)) =>
      match en.get("cases") {
        Some(Array(cases)) => {
          let parsed : Array[String] = []
          for c in cases {
            guard c is Object(cobj) else { continue }
            match cobj.get("name") {
              Some(String(s)) => parsed.push(s)
              _ => ()
            }
          }
          return Enum(parsed)
        }
        _ => ()
      }
    _ => ()
  }
  // Alias type (direct type reference)
  match obj.get("type") {
    Some(t) => return Alias(@json.from_json(t, path=path.add_key("type")))
    _ => ()
  }
  // Handle type (own<T> or borrow<T>)
  match obj.get("handle") {
    Some(h) => return Handle(@json.from_json(h, path=path.add_key("handle")))
    _ => ()
  }
  raise @json.JsonDecodeError((path, "TypeKind: unknown kind"))
}

///|
/// Type definition
pub(all) struct TypeDef {
  name : String?
  kind : TypeKind
  owner : TypeOwner
} derive(Show, Eq, ToJson)

///|
pub impl @json.FromJson for TypeDef with from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "TypeDef: expected object"))
  }
  let name : String? = match obj.get("name") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let kind : TypeKind = match obj.get("kind") {
    Some(k) => @json.from_json(k, path=path.add_key("kind"))
    _ => raise @json.JsonDecodeError((path, "TypeDef: missing kind"))
  }
  let owner : TypeOwner = match obj.get("owner") {
    Some(o) => @json.from_json(o, path=path.add_key("owner"))
    _ => TypeOwner::None
  }
  { name, kind, owner }
}

///|
/// Full resolve structure
pub(all) struct Resolve {
  worlds : Array[World]
  interfaces : Array[Interface]
  types : Array[TypeDef]
  packages : Array[Package]
} derive(Show, Eq, FromJson, ToJson)

///|
/// Input from resolve-json tool
pub(all) struct ResolveInput {
  resolve : Resolve
  world_id : Int
} derive(Show, Eq, FromJson, ToJson)
