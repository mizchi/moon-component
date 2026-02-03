///|
fn world_item_kind(item : @wit.RWorldItem) -> ExternKind {
  match item {
    @wit.RWorldItem::Interface(_) => ExternKind::Instance
    @wit.RWorldItem::Function(_) => ExternKind::Func
    @wit.RWorldItem::Type(_) => ExternKind::Type
  }
}

///|
fn pair_key(a : Int, b : Int) -> String {
  a.to_string() + ":" + b.to_string()
}

///|
fn mark_seen(seen : Map[String, Bool], a : Int, b : Int) -> Bool {
  let key = pair_key(a, b)
  if seen.contains(key) {
    true
  } else {
    seen.set(key, true)
    false
  }
}

///|
fn eq_rtype(
  a_res : @wit.Resolve,
  a_ty : @wit.RType,
  b_res : @wit.Resolve,
  b_ty : @wit.RType,
  seen : Map[String, Bool],
) -> Bool {
  match (a_ty, b_ty) {
    (Bool, Bool)
    | (U8, U8)
    | (U16, U16)
    | (U32, U32)
    | (U64, U64)
    | (S8, S8)
    | (S16, S16)
    | (S32, S32)
    | (S64, S64)
    | (F32, F32)
    | (F64, F64)
    | (Char, Char)
    | (String_, String_) => true
    (Id(a_id), Id(b_id)) => eq_type_def(a_res, a_id, b_res, b_id, seen)
    _ => false
  }
}

///|
fn eq_rtype_opt(
  a_res : @wit.Resolve,
  a_ty : @wit.RType?,
  b_res : @wit.Resolve,
  b_ty : @wit.RType?,
  seen : Map[String, Bool],
) -> Bool {
  match (a_ty, b_ty) {
    (Some(a), Some(b)) => eq_rtype(a_res, a, b_res, b, seen)
    (None, None) => true
    _ => false
  }
}

///|
fn eq_type_def(
  a_res : @wit.Resolve,
  a_id : Int,
  b_res : @wit.Resolve,
  b_id : Int,
  seen : Map[String, Bool],
) -> Bool {
  if mark_seen(seen, a_id, b_id) {
    return true
  }
  let a_alias = unwrap_alias(a_res, a_id)
  let b_alias = unwrap_alias(b_res, b_id)
  match (a_alias, b_alias) {
    (Some(AliasId(a2)), Some(AliasId(b2))) =>
      eq_type_def(a_res, a2, b_res, b2, seen)
    (Some(AliasPrim(a_ty)), Some(AliasPrim(b_ty))) =>
      eq_rtype(a_res, a_ty, b_res, b_ty, seen)
    (Some(AliasId(_)), Some(AliasPrim(_)))
    | (Some(AliasPrim(_)), Some(AliasId(_))) => false
    (Some(AliasId(a2)), None) => eq_type_def(a_res, a2, b_res, b_id, seen)
    (None, Some(AliasId(b2))) => eq_type_def(a_res, a_id, b_res, b2, seen)
    (Some(AliasPrim(_)), None) => false
    (None, Some(AliasPrim(_))) => false
    (None, None) => {
      let a_def = a_res.types[a_id]
      let b_def = b_res.types[b_id]
      eq_type_kind(a_res, a_def.kind, b_res, b_def.kind, seen)
    }
  }
}

///|
priv enum AliasTarget {
  AliasId(Int)
  AliasPrim(@wit.RType)
}

///|
fn unwrap_alias(res : @wit.Resolve, id : Int) -> AliasTarget? {
  let seen : Map[String, Bool] = {}
  unwrap_alias_inner(res, id, seen)
}

///|
fn unwrap_alias_inner(
  res : @wit.Resolve,
  id : Int,
  seen : Map[String, Bool],
) -> AliasTarget? {
  let key = id.to_string()
  if seen.contains(key) {
    return Some(AliasId(id))
  }
  seen.set(key, true)
  let def = res.types[id]
  match def.kind {
    @wit.RTypeKind::Alias(alias_ty) =>
      match alias_ty {
        @wit.RType::Id(next_id) =>
          match unwrap_alias_inner(res, next_id, seen) {
            Some(inner) => Some(inner)
            None => Some(AliasId(next_id))
          }
        _ => Some(AliasPrim(alias_ty))
      }
    _ => None
  }
}

///|
fn eq_type_kind(
  a_res : @wit.Resolve,
  a_kind : @wit.RTypeKind,
  b_res : @wit.Resolve,
  b_kind : @wit.RTypeKind,
  seen : Map[String, Bool],
) -> Bool {
  match (a_kind, b_kind) {
    (@wit.RTypeKind::Record(a_fields), @wit.RTypeKind::Record(b_fields)) => {
      if a_fields.length() != b_fields.length() {
        return false
      }
      for i in 0..<a_fields.length() {
        let a_field = a_fields[i]
        let b_field = b_fields[i]
        if a_field.name != b_field.name {
          return false
        }
        if not(
            eq_rtype(a_res, a_field.field_type, b_res, b_field.field_type, seen),
          ) {
          return false
        }
      }
      true
    }
    (@wit.RTypeKind::Variant(a_cases), @wit.RTypeKind::Variant(b_cases)) => {
      if a_cases.length() != b_cases.length() {
        return false
      }
      for i in 0..<a_cases.length() {
        let a_case = a_cases[i]
        let b_case = b_cases[i]
        if a_case.name != b_case.name {
          return false
        }
        if not(
            eq_rtype_opt(a_res, a_case.case_type, b_res, b_case.case_type, seen),
          ) {
          return false
        }
      }
      true
    }
    (@wit.RTypeKind::List(a), @wit.RTypeKind::List(b)) =>
      eq_rtype(a_res, a, b_res, b, seen)
    (@wit.RTypeKind::Option(a), @wit.RTypeKind::Option(b)) =>
      eq_rtype(a_res, a, b_res, b, seen)
    (
      @wit.RTypeKind::Result(ok=a_ok, err=a_err),
      @wit.RTypeKind::Result(ok=b_ok, err=b_err),
    ) =>
      eq_rtype_opt(a_res, a_ok, b_res, b_ok, seen) &&
      eq_rtype_opt(a_res, a_err, b_res, b_err, seen)
    (@wit.RTypeKind::Tuple(a_items), @wit.RTypeKind::Tuple(b_items)) => {
      if a_items.length() != b_items.length() {
        return false
      }
      for i in 0..<a_items.length() {
        if not(eq_rtype(a_res, a_items[i], b_res, b_items[i], seen)) {
          return false
        }
      }
      true
    }
    (@wit.RTypeKind::Flags(a_names), @wit.RTypeKind::Flags(b_names)) =>
      a_names == b_names
    (@wit.RTypeKind::Enum(a_names), @wit.RTypeKind::Enum(b_names)) =>
      a_names == b_names
    (@wit.RTypeKind::Resource, @wit.RTypeKind::Resource) => true
    (@wit.RTypeKind::Handle(a_h), @wit.RTypeKind::Handle(b_h)) =>
      eq_handle_kind(a_res, a_h, b_res, b_h, seen)
    _ => false
  }
}

///|
fn eq_handle_kind(
  a_res : @wit.Resolve,
  a_kind : @wit.RHandleKind,
  b_res : @wit.Resolve,
  b_kind : @wit.RHandleKind,
  seen : Map[String, Bool],
) -> Bool {
  match (a_kind, b_kind) {
    (@wit.RHandleKind::Own(a_id), @wit.RHandleKind::Own(b_id)) =>
      eq_type_def(a_res, a_id, b_res, b_id, seen)
    (@wit.RHandleKind::Borrow(a_id), @wit.RHandleKind::Borrow(b_id)) =>
      eq_type_def(a_res, a_id, b_res, b_id, seen)
    _ => false
  }
}

///|
fn eq_function(
  a_res : @wit.Resolve,
  a_func : @wit.RFunction,
  b_res : @wit.Resolve,
  b_func : @wit.RFunction,
  seen : Map[String, Bool],
) -> Bool {
  if a_func.kind != b_func.kind {
    return false
  }
  if a_func.params.length() != b_func.params.length() {
    return false
  }
  for i in 0..<a_func.params.length() {
    let (a_name, a_ty) = a_func.params[i]
    let (b_name, b_ty) = b_func.params[i]
    if a_name != b_name {
      return false
    }
    if not(eq_rtype(a_res, a_ty, b_res, b_ty, seen)) {
      return false
    }
  }
  eq_rtype_opt(a_res, a_func.result, b_res, b_func.result, seen)
}

///|
fn eq_interface(
  a_res : @wit.Resolve,
  a_iface : @wit.RInterface,
  b_res : @wit.Resolve,
  b_iface : @wit.RInterface,
  seen : Map[String, Bool],
) -> Bool {
  if a_iface.functions.length() != b_iface.functions.length() {
    return false
  }
  for name, a_func in a_iface.functions {
    match b_iface.functions.get(name) {
      Some(b_func) =>
        if not(eq_function(a_res, a_func, b_res, b_func, seen)) {
          return false
        }
      None => return false
    }
  }
  if a_iface.types.length() != b_iface.types.length() {
    return false
  }
  for name, a_id in a_iface.types {
    match b_iface.types.get(name) {
      Some(b_id) =>
        if not(eq_type_def(a_res, a_id, b_res, b_id, seen)) {
          return false
        }
      None => return false
    }
  }
  true
}

///|
fn eq_world_item(
  a_res : @wit.Resolve,
  a_item : @wit.RWorldItem,
  b_res : @wit.Resolve,
  b_item : @wit.RWorldItem,
  seen : Map[String, Bool],
) -> Bool {
  match (a_item, b_item) {
    (@wit.RWorldItem::Function(a_func), @wit.RWorldItem::Function(b_func)) =>
      eq_function(a_res, a_func, b_res, b_func, seen)
    (@wit.RWorldItem::Interface(a_ref), @wit.RWorldItem::Interface(b_ref)) => {
      let a_iface = a_res.interfaces[a_ref.id]
      let b_iface = b_res.interfaces[b_ref.id]
      eq_interface(a_res, a_iface, b_res, b_iface, seen)
    }
    (@wit.RWorldItem::Type(a_id), @wit.RWorldItem::Type(b_id)) =>
      eq_type_def(a_res, a_id, b_res, b_id, seen)
    _ => false
  }
}

///|
fn world_of(input : @wit.ResolveInput) -> @wit.RWorld {
  input.resolve.worlds[input.world_id]
}

///|
pub fn check_plug_wit(
  socket : @wit.ResolveInput,
  plugs : Array[@wit.ResolveInput],
) -> Result[Unit, String] {
  let socket_world = world_of(socket)
  for name, item in socket_world.imports {
    let kind = world_item_kind(item)
    let mut candidate = false
    let mut matched = false
    for plug_input in plugs {
      let plug_world = world_of(plug_input)
      match plug_world.exports.get(name) {
        Some(plug_item) =>
          if world_item_kind(plug_item) == kind {
            candidate = true
            let seen : Map[String, Bool] = {}
            if eq_world_item(
                socket.resolve,
                item,
                plug_input.resolve,
                plug_item,
                seen,
              ) {
              matched = true
              break
            }
          }
        None => ()
      }
    }
    if candidate && not(matched) {
      return Err("WIT mismatch for import `\{name}`")
    }
  }
  Ok(())
}
