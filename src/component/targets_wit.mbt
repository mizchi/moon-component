///|
pub fn check_func_signature(
  func_name : String,
  func : @wit.RFunction,
  resolved : ResolvedFuncType,
  wit_res : @wit.Resolve,
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  let comp_func = resolved.func
  let space = resolved.space
  if func.params.length() != comp_func.params.length() {
    return Err("param count mismatch for `\{func_name}`")
  }
  let type_map : Map[String, UInt] = {}
  let res_map : Map[String, UInt] = {}
  for i in 0..<func.params.length() {
    let (_, wit_ty) = func.params[i]
    let comp_ty = comp_func.params[i].type_
    match
      check_wit_type(wit_res, wit_ty, comp_ty, space, type_map, res_map, ctx) {
      Ok(_) => ()
      Err(e) =>
        return Err("param \{i.to_string()} mismatch for `\{func_name}`: " + e)
    }
  }
  let wit_result = func.result
  let comp_result = if comp_func.results.length() == 0 {
    None
  } else {
    Some(comp_func.results[0].type_)
  }
  match (wit_result, comp_result) {
    (None, None) => Ok(())
    (Some(wit_ty), Some(comp_ty)) =>
      match
        check_wit_type(wit_res, wit_ty, comp_ty, space, type_map, res_map, ctx) {
        Ok(_) => Ok(())
        Err(e) => Err("result mismatch for `\{func_name}`: " + e)
      }
    _ => Err("result count mismatch for `\{func_name}`")
  }
}

///|
pub fn check_interface(
  iface : @wit.RInterface,
  export_set : InstanceExportSet,
  wit_res : @wit.Resolve,
  ctx : TypeResolveContext,
  label : String,
  errors : Array[String],
) -> Unit {
  let export_map : Map[String, InstanceExport] = {}
  for exp in export_set.exports {
    export_map.set(bytes_to_string(exp.name), exp)
  }
  let matched : Map[String, Bool] = {}
  for name, func in iface.functions {
    match export_map.get(name) {
      Some(exp) => {
        matched.set(name, true)
        match resolve_func_type_in_space(ctx, export_set.space, exp.type_ref) {
          Some(resolved) =>
            match check_func_signature(name, func, resolved, wit_res, ctx) {
              Ok(_) => ()
              Err(e) => errors.push("\{label} func `\{name}`: " + e)
            }
          None => errors.push("\{label} func `\{name}`: not a function type")
        }
      }
      None => errors.push("\{label} missing func `\{name}`")
    }
  }
  for name, _ in export_map {
    if not(matched.contains(name)) {
      errors.push("\{label} extra export `\{name}`")
    }
  }
}

///|
fn check_wit_type(
  wit_res : @wit.Resolve,
  wit_ty : @wit.RType,
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match wit_ty {
    @wit.RType::Bool =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::Bool) => Ok(())
        _ => Err("expected bool")
      }
    @wit.RType::U8 =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::U8) => Ok(())
        _ => Err("expected u8")
      }
    @wit.RType::U16 =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::U16) => Ok(())
        _ => Err("expected u16")
      }
    @wit.RType::U32 =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::U32) => Ok(())
        _ => Err("expected u32")
      }
    @wit.RType::U64 =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::U64) => Ok(())
        _ => Err("expected u64")
      }
    @wit.RType::S8 =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::S8) => Ok(())
        _ => Err("expected s8")
      }
    @wit.RType::S16 =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::S16) => Ok(())
        _ => Err("expected s16")
      }
    @wit.RType::S32 =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::S32) => Ok(())
        _ => Err("expected s32")
      }
    @wit.RType::S64 =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::S64) => Ok(())
        _ => Err("expected s64")
      }
    @wit.RType::F32 =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::F32) => Ok(())
        _ => Err("expected f32")
      }
    @wit.RType::F64 =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::F64) => Ok(())
        _ => Err("expected f64")
      }
    @wit.RType::Char =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::Char) => Ok(())
        _ => Err("expected char")
      }
    @wit.RType::String_ =>
      match comp_val {
        ComponentValType::Primitive(PrimitiveType::String) => Ok(())
        _ => Err("expected string")
      }
    @wit.RType::Id(id) =>
      check_wit_type_def(wit_res, id, comp_val, space, type_map, res_map, ctx)
  }
}

///|
fn check_wit_type_def(
  wit_res : @wit.Resolve,
  id : Int,
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  let def = wit_res.types[id].kind
  match def {
    @wit.RTypeKind::Alias(inner) =>
      check_wit_type(wit_res, inner, comp_val, space, type_map, res_map, ctx)
    @wit.RTypeKind::Record(fields) =>
      check_wit_record(
        wit_res, id, fields, comp_val, space, type_map, res_map, ctx,
      )
    @wit.RTypeKind::Variant(cases) =>
      check_wit_variant(
        wit_res, id, cases, comp_val, space, type_map, res_map, ctx,
      )
    @wit.RTypeKind::List(inner) =>
      check_wit_list(
        wit_res, id, inner, comp_val, space, type_map, res_map, ctx,
      )
    @wit.RTypeKind::Option(inner) =>
      check_wit_option(
        wit_res, id, inner, comp_val, space, type_map, res_map, ctx,
      )
    @wit.RTypeKind::Result(ok~, err~) =>
      check_wit_result(
        wit_res, id, ok, err, comp_val, space, type_map, res_map, ctx,
      )
    @wit.RTypeKind::Tuple(items) =>
      check_wit_tuple(
        wit_res, id, items, comp_val, space, type_map, res_map, ctx,
      )
    @wit.RTypeKind::Flags(names) =>
      check_wit_flags(id, names, comp_val, space, type_map, res_map, ctx)
    @wit.RTypeKind::Enum(names) =>
      check_wit_enum(id, names, comp_val, space, type_map, res_map, ctx)
    @wit.RTypeKind::Resource =>
      check_wit_resource(id, comp_val, space, type_map, res_map, ctx)
    @wit.RTypeKind::Handle(kind) =>
      check_wit_handle(kind, comp_val, space, type_map, res_map, ctx)
  }
}

///|
fn check_wit_record(
  wit_res : @wit.Resolve,
  id : Int,
  fields : Array[@wit.RRecordField],
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match comp_val {
    ComponentValType::Record(comp_fields) => {
      if fields.length() != comp_fields.length() {
        return Err("record field count mismatch")
      }
      for i in 0..<fields.length() {
        let wf = fields[i]
        let cf = comp_fields[i]
        if wf.name != bytes_to_string(cf.name) {
          return Err("record field name mismatch")
        }
        match
          check_wit_type(
            wit_res,
            wf.field_type,
            cf.type_,
            space,
            type_map,
            res_map,
            ctx,
          ) {
          Ok(_) => ()
          Err(e) => return Err("record field `\{wf.name}`: " + e)
        }
      }
      Ok(())
    }
    ComponentValType::TypeIndex(idx) =>
      check_type_index(
        id,
        idx,
        space,
        type_map,
        res_map,
        (def, def_space) => check_wit_record(
          wit_res, id, fields, def, def_space, type_map, res_map, ctx,
        ),
        ctx,
      )
    _ => Err("expected record")
  }
}

///|
fn check_wit_variant(
  wit_res : @wit.Resolve,
  id : Int,
  cases : Array[@wit.RVariantCase],
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match comp_val {
    ComponentValType::Variant(comp_cases) => {
      if cases.length() != comp_cases.length() {
        return Err("variant case count mismatch")
      }
      for i in 0..<cases.length() {
        let wc = cases[i]
        let cc = comp_cases[i]
        if wc.name != bytes_to_string(cc.name) {
          return Err("variant case name mismatch")
        }
        match (wc.case_type, cc.type_) {
          (None, None) => ()
          (Some(wt), Some(ct)) =>
            match
              check_wit_type(wit_res, wt, ct, space, type_map, res_map, ctx) {
              Ok(_) => ()
              Err(e) => return Err("variant case `\{wc.name}`: " + e)
            }
          _ => return Err("variant case payload mismatch")
        }
      }
      Ok(())
    }
    ComponentValType::TypeIndex(idx) =>
      check_type_index(
        id,
        idx,
        space,
        type_map,
        res_map,
        (def, def_space) => check_wit_variant(
          wit_res, id, cases, def, def_space, type_map, res_map, ctx,
        ),
        ctx,
      )
    _ => Err("expected variant")
  }
}

///|
fn check_wit_list(
  wit_res : @wit.Resolve,
  id : Int,
  inner : @wit.RType,
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match comp_val {
    ComponentValType::List(ct) =>
      check_wit_type(wit_res, inner, ct, space, type_map, res_map, ctx)
    ComponentValType::TypeIndex(idx) =>
      check_type_index(
        id,
        idx,
        space,
        type_map,
        res_map,
        (def, def_space) => check_wit_list(
          wit_res, id, inner, def, def_space, type_map, res_map, ctx,
        ),
        ctx,
      )
    _ => Err("expected list")
  }
}

///|
fn check_wit_option(
  wit_res : @wit.Resolve,
  id : Int,
  inner : @wit.RType,
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match comp_val {
    ComponentValType::Option(ct) =>
      check_wit_type(wit_res, inner, ct, space, type_map, res_map, ctx)
    ComponentValType::TypeIndex(idx) =>
      check_type_index(
        id,
        idx,
        space,
        type_map,
        res_map,
        (def, def_space) => check_wit_option(
          wit_res, id, inner, def, def_space, type_map, res_map, ctx,
        ),
        ctx,
      )
    _ => Err("expected option")
  }
}

///|
fn check_wit_result(
  wit_res : @wit.Resolve,
  id : Int,
  ok : @wit.RType?,
  err : @wit.RType?,
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match comp_val {
    ComponentValType::Result(ok2, err2) => {
      match (ok, ok2) {
        (None, None) => ()
        (Some(wt), Some(ct)) =>
          match check_wit_type(wit_res, wt, ct, space, type_map, res_map, ctx) {
            Ok(_) => ()
            Err(e) => return Err("result ok: " + e)
          }
        _ => return Err("result ok mismatch")
      }
      match (err, err2) {
        (None, None) => ()
        (Some(wt), Some(ct)) =>
          match check_wit_type(wit_res, wt, ct, space, type_map, res_map, ctx) {
            Ok(_) => ()
            Err(e) => return Err("result err: " + e)
          }
        _ => return Err("result err mismatch")
      }
      Ok(())
    }
    ComponentValType::TypeIndex(idx) =>
      check_type_index(
        id,
        idx,
        space,
        type_map,
        res_map,
        (def, def_space) => check_wit_result(
          wit_res, id, ok, err, def, def_space, type_map, res_map, ctx,
        ),
        ctx,
      )
    _ => Err("expected result")
  }
}

///|
fn check_wit_tuple(
  wit_res : @wit.Resolve,
  id : Int,
  items : Array[@wit.RType],
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match comp_val {
    ComponentValType::Tuple(values) => {
      if items.length() != values.length() {
        return Err("tuple length mismatch")
      }
      for i in 0..<items.length() {
        match
          check_wit_type(
            wit_res,
            items[i],
            values[i],
            space,
            type_map,
            res_map,
            ctx,
          ) {
          Ok(_) => ()
          Err(e) => return Err("tuple item \{i.to_string()}: " + e)
        }
      }
      Ok(())
    }
    ComponentValType::TypeIndex(idx) =>
      check_type_index(
        id,
        idx,
        space,
        type_map,
        res_map,
        (def, def_space) => check_wit_tuple(
          wit_res, id, items, def, def_space, type_map, res_map, ctx,
        ),
        ctx,
      )
    _ => Err("expected tuple")
  }
}

///|
fn check_wit_flags(
  id : Int,
  names : Array[String],
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match comp_val {
    ComponentValType::Flags(comp_names) => {
      if names.length() != comp_names.length() {
        return Err("flags length mismatch")
      }
      for i in 0..<names.length() {
        if names[i] != bytes_to_string(comp_names[i]) {
          return Err("flags name mismatch")
        }
      }
      Ok(())
    }
    ComponentValType::TypeIndex(idx) =>
      check_type_index(
        id,
        idx,
        space,
        type_map,
        res_map,
        (def, def_space) => check_wit_flags(
          id, names, def, def_space, type_map, res_map, ctx,
        ),
        ctx,
      )
    _ => Err("expected flags")
  }
}

///|
fn check_wit_enum(
  id : Int,
  names : Array[String],
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match comp_val {
    ComponentValType::Enum(comp_names) => {
      if names.length() != comp_names.length() {
        return Err("enum length mismatch")
      }
      for i in 0..<names.length() {
        if names[i] != bytes_to_string(comp_names[i]) {
          return Err("enum name mismatch")
        }
      }
      Ok(())
    }
    ComponentValType::TypeIndex(idx) =>
      check_type_index(
        id,
        idx,
        space,
        type_map,
        res_map,
        (def, def_space) => check_wit_enum(
          id, names, def, def_space, type_map, res_map, ctx,
        ),
        ctx,
      )
    _ => Err("expected enum")
  }
}

///|
fn check_wit_resource(
  id : Int,
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  _res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match comp_val {
    ComponentValType::TypeIndex(idx) => {
      let key = space_key(space, id)
      match type_map.get(key) {
        Some(existing) =>
          if existing != idx {
            return Err("type index mismatch")
          }
        None => type_map.set(key, idx)
      }
      match resolve_entry(ctx, space, idx) {
        Some((def, _def_space)) =>
          match def {
            ComponentTypeDef::Resource => Ok(())
            _ => Err("expected resource type")
          }
        None => Err("type index out of range")
      }
    }
    _ => Err("expected resource type index")
  }
}

///|
fn check_wit_handle(
  kind : @wit.RHandleKind,
  comp_val : ComponentValType,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match comp_val {
    ComponentValType::Own(idx) => {
      let res_id = match kind {
        @wit.RHandleKind::Own(id) => id
        @wit.RHandleKind::Borrow(id) => id
      }
      let key = space_key(space, res_id)
      match res_map.get(key) {
        Some(existing) =>
          if existing != idx {
            return Err("resource handle mismatch")
          }
        None => res_map.set(key, idx)
      }
      match resolve_entry(ctx, space, idx) {
        Some((def, _def_space)) =>
          match def {
            ComponentTypeDef::Resource => Ok(())
            _ => Err("expected resource type")
          }
        None => Err("resource index out of range")
      }
    }
    ComponentValType::Borrow(idx) => {
      let res_id = match kind {
        @wit.RHandleKind::Own(id) => id
        @wit.RHandleKind::Borrow(id) => id
      }
      let key = space_key(space, res_id)
      match res_map.get(key) {
        Some(existing) =>
          if existing != idx {
            return Err("resource handle mismatch")
          }
        None => res_map.set(key, idx)
      }
      match resolve_entry(ctx, space, idx) {
        Some((def, _def_space)) =>
          match def {
            ComponentTypeDef::Resource => Ok(())
            _ => Err("expected resource type")
          }
        None => Err("resource index out of range")
      }
    }
    ComponentValType::TypeIndex(idx) =>
      check_type_index_for_handle(idx, kind, space, type_map, res_map, ctx)
    _ => Err("expected handle")
  }
}

///|
fn check_type_index_for_handle(
  idx : UInt,
  kind : @wit.RHandleKind,
  space : TypeSpace,
  type_map : Map[String, UInt],
  res_map : Map[String, UInt],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  match resolve_entry(ctx, space, idx) {
    Some((def, def_space)) =>
      match def {
        ComponentTypeDef::Defined(def_val) =>
          check_wit_handle(kind, def_val, def_space, type_map, res_map, ctx)
        _ => Err("handle type refers to non-defined type")
      }
    None => Err("type index out of range")
  }
}

///|
fn check_type_index(
  id : Int,
  idx : UInt,
  space : TypeSpace,
  type_map : Map[String, UInt],
  _res_map : Map[String, UInt],
  next : (ComponentValType, TypeSpace) -> Result[Unit, String],
  ctx : TypeResolveContext,
) -> Result[Unit, String] {
  let key = space_key(space, id)
  match type_map.get(key) {
    Some(existing) => if existing != idx { return Err("type index mismatch") }
    None => type_map.set(key, idx)
  }
  match resolve_entry(ctx, space, idx) {
    Some((def, def_space)) =>
      match def {
        ComponentTypeDef::Defined(def_val) => next(def_val, def_space)
        _ => Err("type index refers to non-defined type")
      }
    None => Err("type index out of range")
  }
}
