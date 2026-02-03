///|

///|
fn bytes_to_string(bytes : Bytes) -> String {
  let chars : Array[Char] = []
  for b in bytes {
    chars.push(b.to_char())
  }
  String::from_array(chars)
}

///|
fn collect_world_candidates(
  items : Map[String, @wit.RWorldItem],
  resolve : @wit.Resolve,
) -> Array[WorldCandidate] {
  let candidates : Array[WorldCandidate] = []
  for name, item in items {
    let kind = world_item_kind(item)
    let names = world_item_candidates(resolve, name, item)
    candidates.push({ names, kind, item })
  }
  candidates
}

///|
fn package_name_str(pkg_name : @wit.RPackageName) -> String {
  let base = pkg_name.ns + ":" + pkg_name.name
  match pkg_name.version {
    Some(v) => base + "@" + v
    None => base
  }
}

///|
fn world_item_candidates(
  resolve : @wit.Resolve,
  key : String,
  item : @wit.RWorldItem,
) -> Array[String] {
  let out : Array[String] = [key]
  match item {
    @wit.RWorldItem::Interface(iface_ref) => {
      let iface = resolve.interfaces[iface_ref.id]
      match iface.name {
        Some(name) =>
          match iface.pkg {
            Some(pkg_id) => {
              let pkg = resolve.packages[pkg_id]
              let pkg_name = package_name_str(pkg.name)
              out.push(pkg_name + "/" + name)
            }
            None => out.push(name)
          }
        None => ()
      }
    }
    @wit.RWorldItem::Function(_) => ()
    @wit.RWorldItem::Type(_) => ()
  }
  out
}

///|
priv struct WorldCandidate {
  names : Array[String]
  kind : ExternKind
  item : @wit.RWorldItem
}

///|
priv struct InstanceExportSet {
  exports : Array[InstanceExport]
  space : TypeSpace
}

///|
priv struct TypeSpace {
  id : String
  entries : Array[InstanceTypeEntry]
  outer : TypeSpace?
}

///|
priv struct ResolvedFuncType {
  func : ComponentFuncType
  space : TypeSpace
}

///|
priv struct TypeResolveContext {
  detail : ComponentDetail
  global_space : TypeSpace
  instance_cache : Map[UInt, InstanceExportSet]
}

///|
fn build_import_map(
  imports : Array[ComponentImportDetail],
  errors : Array[String],
) -> Map[String, ComponentImportDetail] {
  let map : Map[String, ComponentImportDetail] = {}
  for imp in imports {
    let name = bytes_to_string(imp.name)
    match map.get(name) {
      Some(existing) =>
        if existing.kind != imp.kind {
          errors.push(
            "import kind mismatch for `\{name}`: \{existing.kind.to_string()} vs \{imp.kind.to_string()}",
          )
        }
      None => map.set(name, imp)
    }
  }
  map
}

///|
fn build_export_map(
  exports : Array[ComponentExportDetail],
  errors : Array[String],
) -> Map[String, ComponentExportDetail] {
  let map : Map[String, ComponentExportDetail] = {}
  for exp in exports {
    let name = bytes_to_string(exp.name)
    match map.get(name) {
      Some(existing) =>
        if existing.kind != exp.kind {
          errors.push(
            "export kind mismatch for `\{name}`: \{existing.kind.to_string()} vs \{exp.kind.to_string()}",
          )
        }
      None => map.set(name, exp)
    }
  }
  map
}

///|
fn find_import_by_names(
  map : Map[String, ComponentImportDetail],
  names : Array[String],
) -> (String, ComponentImportDetail)? {
  for name in names {
    match map.get(name) {
      Some(item) => return Some((name, item))
      None => ()
    }
  }
  None
}

///|
fn find_export_by_names(
  map : Map[String, ComponentExportDetail],
  names : Array[String],
) -> (String, ComponentExportDetail)? {
  for name in names {
    match map.get(name) {
      Some(item) => return Some((name, item))
      None => ()
    }
  }
  None
}

///|
fn types_to_entries(
  types : Array[ComponentTypeDef],
) -> Array[InstanceTypeEntry] {
  let entries : Array[InstanceTypeEntry] = []
  for ty in types {
    entries.push(InstanceTypeEntry::Local(ty))
  }
  entries
}

///|
fn build_global_space(types : Array[ComponentTypeDef]) -> TypeSpace {
  { id: "global", entries: types_to_entries(types), outer: None }
}

///|
fn build_nested_global_space(
  types : Array[ComponentTypeDef],
  outer : TypeSpace,
) -> TypeSpace {
  {
    id: outer.id + "/global",
    entries: types_to_entries(types),
    outer: Some(outer),
  }
}

///|
fn build_instance_space(
  entries : Array[InstanceTypeEntry],
  outer : TypeSpace,
) -> TypeSpace {
  { id: outer.id + "/local", entries, outer: Some(outer) }
}

///|
fn space_key(space : TypeSpace, id : Int) -> String {
  space.id + ":" + id.to_string()
}

///|
fn resolve_outer_space(space : TypeSpace, count : UInt) -> TypeSpace? {
  let mut current = space
  let mut remaining = count + 1U
  while remaining > 0U {
    match current.outer {
      Some(outer_space) => {
        current = outer_space
        remaining = remaining - 1U
      }
      None => return None
    }
  }
  Some(current)
}

///|
fn get_instance_export_set(
  ctx : TypeResolveContext,
  index : UInt,
) -> Result[InstanceExportSet, String] {
  match ctx.instance_cache.get(index) {
    Some(cached) => Ok(cached)
    None => {
      let resolved = resolve_instance_exports_from_instance_index(
        ctx.detail,
        index,
        ctx.global_space,
      )
      match resolved {
        Ok(set) => {
          ctx.instance_cache.set(index, set)
          Ok(set)
        }
        Err(e) => Err(e)
      }
    }
  }
}

///|
fn resolve_alias_export(
  ctx : TypeResolveContext,
  instance_idx : UInt,
  name : Bytes,
) -> (ComponentTypeDef, TypeSpace)? {
  let export_set = match get_instance_export_set(ctx, instance_idx) {
    Ok(set) => set
    Err(_) => return None
  }
  for exp in export_set.exports {
    if exp.name == name {
      match exp.type_ref {
        ComponentTypeRef::Type(TypeBounds::Eq(idx)) =>
          return resolve_entry(ctx, export_set.space, idx)
        _ => return None
      }
    }
  }
  None
}

///|
fn resolve_entry(
  ctx : TypeResolveContext,
  space : TypeSpace,
  idx : UInt,
) -> (ComponentTypeDef, TypeSpace)? {
  if idx >= space.entries.length().reinterpret_as_uint() {
    return None
  }
  match space.entries[idx.reinterpret_as_int()] {
    InstanceTypeEntry::Local(def) => Some((def, space))
    InstanceTypeEntry::Alias(InstanceAliasTarget::Outer(count, outer_idx)) =>
      match resolve_outer_space(space, count) {
        Some(outer_space) => resolve_entry(ctx, outer_space, outer_idx)
        None => None
      }
    InstanceTypeEntry::Alias(InstanceAliasTarget::Export(instance_idx, name)) =>
      resolve_alias_export(ctx, instance_idx, name)
    InstanceTypeEntry::Alias(InstanceAliasTarget::Unknown) => None
  }
}

///|
fn resolve_func_type_in_space(
  ctx : TypeResolveContext,
  space : TypeSpace,
  type_ref : ComponentTypeRef,
) -> ResolvedFuncType? {
  match type_ref {
    ComponentTypeRef::Func(idx) =>
      match resolve_entry(ctx, space, idx) {
        Some((def, def_space)) =>
          match def {
            ComponentTypeDef::Func(ft) => Some({ func: ft, space: def_space })
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
fn resolve_instance_exports_from_type_ref(
  detail : ComponentDetail,
  type_ref : ComponentTypeRef,
  outer_space : TypeSpace,
) -> Result[InstanceExportSet, String] {
  match type_ref {
    ComponentTypeRef::Instance(idx) => {
      if idx >= detail.types.length().reinterpret_as_uint() {
        return Err("instance type index out of range")
      }
      match detail.types[idx.reinterpret_as_int()] {
        ComponentTypeDef::Instance(def) => {
          let space = build_instance_space(def.entries, outer_space)
          Ok({ exports: def.exports, space })
        }
        _ => Err("instance type is not an instance definition")
      }
    }
    _ => Err("expected instance type reference")
  }
}

///|
fn resolve_instance_exports_from_instance_index(
  detail : ComponentDetail,
  index : UInt,
  outer_space : TypeSpace,
) -> Result[InstanceExportSet, String] {
  if index < detail.imported_instances.length().reinterpret_as_uint() {
    let type_ref = detail.imported_instances[index.reinterpret_as_int()]
    return resolve_instance_exports_from_type_ref(detail, type_ref, outer_space)
  }
  let def_idx = index - detail.imported_instances.length().reinterpret_as_uint()
  if def_idx >= detail.instances.length().reinterpret_as_uint() {
    return Err("instance index out of range")
  }
  match detail.instances[def_idx.reinterpret_as_int()] {
    ComponentInstanceDef::Instantiate(component_index) =>
      resolve_instance_exports_from_component_index(
        detail, component_index, outer_space,
      )
    ComponentInstanceDef::FromExports(_) =>
      Err("instance exports lack type information")
  }
}

///|
fn resolve_instance_exports_from_component_index(
  detail : ComponentDetail,
  index : UInt,
  outer_space : TypeSpace,
) -> Result[InstanceExportSet, String] {
  if index < detail.imported_components.length().reinterpret_as_uint() {
    return Err("component index refers to import")
  }
  let def_idx = index -
    detail.imported_components.length().reinterpret_as_uint()
  if def_idx >= detail.components.length().reinterpret_as_uint() {
    return Err("component index out of range")
  }
  let nested = match
    parse_component_detail(detail.components[def_idx.reinterpret_as_int()]) {
    Ok(v) => v
    Err(e) => return Err("parse nested component failed: " + e.to_string())
  }
  let exports : Array[InstanceExport] = []
  for exp in nested.exports {
    match exp.type_ref {
      Some(type_ref) => exports.push({ name: exp.name, type_ref })
      None => return Err("nested component export lacks type")
    }
  }
  let space = build_nested_global_space(nested.types, outer_space)
  Ok({ exports, space })
}

///|
fn check_type_bounds(
  a : TypeBounds,
  b : TypeBounds,
  ctx_a : TypeResolveContext,
  ctx_b : TypeResolveContext,
  space_a : TypeSpace,
  space_b : TypeSpace,
  type_map : Map[String, String],
  res_map : Map[String, String],
  visiting : Map[String, Bool],
) -> Result[Unit, String] {
  match (a, b) {
    (TypeBounds::SubResource, TypeBounds::SubResource) => Ok(())
    (TypeBounds::Eq(a_idx), TypeBounds::Eq(b_idx)) =>
      check_type_index_pair(
        a_idx, b_idx, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
      )
    _ => Err("type bounds mismatch")
  }
}

///|
fn check_type_index_pair(
  a_idx : UInt,
  b_idx : UInt,
  ctx_a : TypeResolveContext,
  ctx_b : TypeResolveContext,
  space_a : TypeSpace,
  space_b : TypeSpace,
  type_map : Map[String, String],
  res_map : Map[String, String],
  visiting : Map[String, Bool],
) -> Result[Unit, String] {
  let key_a = space_key(space_a, a_idx.reinterpret_as_int())
  let key_b = space_key(space_b, b_idx.reinterpret_as_int())
  match type_map.get(key_a) {
    Some(existing) =>
      if existing != key_b {
        return Err("type index mapping mismatch")
      }
    None => type_map.set(key_a, key_b)
  }
  let visit_key = key_a + "->" + key_b
  if visiting.contains(visit_key) {
    return Ok(())
  }
  visiting.set(visit_key, true)
  let def_a = resolve_entry(ctx_a, space_a, a_idx)
  let def_b = resolve_entry(ctx_b, space_b, b_idx)
  match (def_a, def_b) {
    (
      Some((ComponentTypeDef::Defined(val_a), space_a2)),
      Some((ComponentTypeDef::Defined(val_b), space_b2)),
    ) =>
      check_val_type(
        val_a, val_b, ctx_a, ctx_b, space_a2, space_b2, type_map, res_map, visiting,
      )
    (
      Some((ComponentTypeDef::Resource, _)),
      Some((ComponentTypeDef::Resource, _)),
    ) => Ok(())
    (
      Some((ComponentTypeDef::Func(fn_a), space_a2)),
      Some((ComponentTypeDef::Func(fn_b), space_b2)),
    ) =>
      check_func_type(
        fn_a, fn_b, ctx_a, ctx_b, space_a2, space_b2, type_map, res_map, visiting,
      )
    (
      Some((ComponentTypeDef::Instance(inst_a), space_a2)),
      Some((ComponentTypeDef::Instance(inst_b), space_b2)),
    ) => {
      let inst_space_a = build_instance_space(inst_a.entries, space_a2)
      let inst_space_b = build_instance_space(inst_b.entries, space_b2)
      check_instance_type(
        inst_a, inst_b, ctx_a, ctx_b, inst_space_a, inst_space_b,
      )
    }
    _ => Err("type definition mismatch")
  }
}

///|
fn check_val_type(
  a : ComponentValType,
  b : ComponentValType,
  ctx_a : TypeResolveContext,
  ctx_b : TypeResolveContext,
  space_a : TypeSpace,
  space_b : TypeSpace,
  type_map : Map[String, String],
  res_map : Map[String, String],
  visiting : Map[String, Bool],
) -> Result[Unit, String] {
  match (a, b) {
    (ComponentValType::Primitive(pa), ComponentValType::Primitive(pb)) =>
      if pa == pb {
        Ok(())
      } else {
        Err("primitive mismatch")
      }
    (ComponentValType::List(ta), ComponentValType::List(tb)) =>
      check_val_type(
        ta, tb, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
      )
    (ComponentValType::Map(ka, va), ComponentValType::Map(kb, vb)) => {
      match
        check_val_type(
          ka, kb, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
        ) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      check_val_type(
        va, vb, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
      )
    }
    (ComponentValType::Record(ra), ComponentValType::Record(rb)) => {
      if ra.length() != rb.length() {
        return Err("record length mismatch")
      }
      for i in 0..<ra.length() {
        let fa = ra[i]
        let fb = rb[i]
        if fa.name != fb.name {
          return Err("record field name mismatch")
        }
        match
          check_val_type(
            fa.type_,
            fb.type_,
            ctx_a,
            ctx_b,
            space_a,
            space_b,
            type_map,
            res_map,
            visiting,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      Ok(())
    }
    (ComponentValType::Variant(va), ComponentValType::Variant(vb)) => {
      if va.length() != vb.length() {
        return Err("variant length mismatch")
      }
      for i in 0..<va.length() {
        let ca = va[i]
        let cb = vb[i]
        if ca.name != cb.name {
          return Err("variant case name mismatch")
        }
        match (ca.type_, cb.type_) {
          (None, None) => ()
          (Some(ta), Some(tb)) =>
            match
              check_val_type(
                ta, tb, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
              ) {
              Ok(_) => ()
              Err(e) => return Err(e)
            }
          _ => return Err("variant payload mismatch")
        }
      }
      Ok(())
    }
    (ComponentValType::Tuple(ta), ComponentValType::Tuple(tb)) => {
      if ta.length() != tb.length() {
        return Err("tuple length mismatch")
      }
      for i in 0..<ta.length() {
        match
          check_val_type(
            ta[i],
            tb[i],
            ctx_a,
            ctx_b,
            space_a,
            space_b,
            type_map,
            res_map,
            visiting,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      Ok(())
    }
    (ComponentValType::Flags(na), ComponentValType::Flags(nb)) =>
      if na == nb {
        Ok(())
      } else {
        Err("flags mismatch")
      }
    (ComponentValType::Enum(na), ComponentValType::Enum(nb)) =>
      if na == nb {
        Ok(())
      } else {
        Err("enum mismatch")
      }
    (ComponentValType::Option(ta), ComponentValType::Option(tb)) =>
      check_val_type(
        ta, tb, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
      )
    (ComponentValType::Result(oka, erra), ComponentValType::Result(okb, errb)) => {
      match (oka, okb) {
        (None, None) => ()
        (Some(ta), Some(tb)) =>
          match
            check_val_type(
              ta, tb, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
            ) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        _ => return Err("result ok mismatch")
      }
      match (erra, errb) {
        (None, None) => ()
        (Some(ta), Some(tb)) =>
          match
            check_val_type(
              ta, tb, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
            ) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        _ => return Err("result err mismatch")
      }
      Ok(())
    }
    (ComponentValType::Own(a_idx), ComponentValType::Own(b_idx)) =>
      check_resource_handle(
        a_idx, b_idx, ctx_a, ctx_b, space_a, space_b, res_map,
      )
    (ComponentValType::Borrow(a_idx), ComponentValType::Borrow(b_idx)) =>
      check_resource_handle(
        a_idx, b_idx, ctx_a, ctx_b, space_a, space_b, res_map,
      )
    (ComponentValType::TypeIndex(a_idx), ComponentValType::TypeIndex(b_idx)) =>
      check_type_index_pair(
        a_idx, b_idx, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
      )
    _ => Err("value type mismatch")
  }
}

///|
fn check_resource_handle(
  a_idx : UInt,
  b_idx : UInt,
  ctx_a : TypeResolveContext,
  ctx_b : TypeResolveContext,
  space_a : TypeSpace,
  space_b : TypeSpace,
  res_map : Map[String, String],
) -> Result[Unit, String] {
  let key_a = space_key(space_a, a_idx.reinterpret_as_int())
  let key_b = space_key(space_b, b_idx.reinterpret_as_int())
  match res_map.get(key_a) {
    Some(existing) =>
      if existing != key_b {
        return Err("resource mapping mismatch")
      }
    None => res_map.set(key_a, key_b)
  }
  let res_a = resolve_entry(ctx_a, space_a, a_idx)
  let res_b = resolve_entry(ctx_b, space_b, b_idx)
  match (res_a, res_b) {
    (
      Some((ComponentTypeDef::Resource, _)),
      Some((ComponentTypeDef::Resource, _)),
    ) => Ok(())
    _ => Err("resource type mismatch")
  }
}

///|
fn check_func_type(
  a : ComponentFuncType,
  b : ComponentFuncType,
  ctx_a : TypeResolveContext,
  ctx_b : TypeResolveContext,
  space_a : TypeSpace,
  space_b : TypeSpace,
  type_map : Map[String, String],
  res_map : Map[String, String],
  visiting : Map[String, Bool],
) -> Result[Unit, String] {
  if a.params.length() != b.params.length() {
    return Err("param count mismatch")
  }
  if a.results.length() != b.results.length() {
    return Err("result count mismatch")
  }
  for i in 0..<a.params.length() {
    let pa = a.params[i]
    let pb = b.params[i]
    match
      check_val_type(
        pa.type_,
        pb.type_,
        ctx_a,
        ctx_b,
        space_a,
        space_b,
        type_map,
        res_map,
        visiting,
      ) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  for i in 0..<a.results.length() {
    let ra = a.results[i]
    let rb = b.results[i]
    match
      check_val_type(
        ra.type_,
        rb.type_,
        ctx_a,
        ctx_b,
        space_a,
        space_b,
        type_map,
        res_map,
        visiting,
      ) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  Ok(())
}

///|
fn check_instance_type(
  a : InstanceTypeDef,
  b : InstanceTypeDef,
  ctx_a : TypeResolveContext,
  ctx_b : TypeResolveContext,
  space_a : TypeSpace,
  space_b : TypeSpace,
) -> Result[Unit, String] {
  let export_map_b : Map[String, InstanceExport] = {}
  for exp in b.exports {
    export_map_b.set(exp.name.to_string(), exp)
  }
  let matched : Map[String, Bool] = {}
  for exp_a in a.exports {
    match export_map_b.get(exp_a.name.to_string()) {
      Some(exp_b) => {
        matched.set(exp_a.name.to_string(), true)
        let type_map : Map[String, String] = {}
        let res_map : Map[String, String] = {}
        let visiting : Map[String, Bool] = {}
        match
          check_type_ref(
            exp_a.type_ref,
            exp_b.type_ref,
            ctx_a,
            ctx_b,
            space_a,
            space_b,
            type_map,
            res_map,
            visiting,
          ) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      None => return Err("instance export missing")
    }
  }
  for name, _ in export_map_b {
    if not(matched.contains(name)) {
      return Err("instance export extra")
    }
  }
  Ok(())
}

///|
fn check_type_ref(
  a : ComponentTypeRef,
  b : ComponentTypeRef,
  ctx_a : TypeResolveContext,
  ctx_b : TypeResolveContext,
  space_a : TypeSpace,
  space_b : TypeSpace,
  type_map : Map[String, String],
  res_map : Map[String, String],
  visiting : Map[String, Bool],
) -> Result[Unit, String] {
  match (a, b) {
    (ComponentTypeRef::Func(a_idx), ComponentTypeRef::Func(b_idx)) =>
      match
        (
          resolve_entry(ctx_a, space_a, a_idx),
          resolve_entry(ctx_b, space_b, b_idx),
        ) {
        (
          Some((ComponentTypeDef::Func(fa), sa)),
          Some((ComponentTypeDef::Func(fb), sb)),
        ) =>
          check_func_type(
            fa, fb, ctx_a, ctx_b, sa, sb, type_map, res_map, visiting,
          )
        _ => Err("function type mismatch")
      }
    (ComponentTypeRef::Value(va), ComponentTypeRef::Value(vb)) =>
      check_val_type(
        va, vb, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
      )
    (ComponentTypeRef::Type(ta), ComponentTypeRef::Type(tb)) =>
      check_type_bounds(
        ta, tb, ctx_a, ctx_b, space_a, space_b, type_map, res_map, visiting,
      )
    (ComponentTypeRef::Instance(a_idx), ComponentTypeRef::Instance(b_idx)) =>
      match
        (
          resolve_entry(ctx_a, space_a, a_idx),
          resolve_entry(ctx_b, space_b, b_idx),
        ) {
        (
          Some((ComponentTypeDef::Instance(inst_a), sa)),
          Some((ComponentTypeDef::Instance(inst_b), sb)),
        ) => {
          let inst_space_a = build_instance_space(inst_a.entries, sa)
          let inst_space_b = build_instance_space(inst_b.entries, sb)
          check_instance_type(
            inst_a, inst_b, ctx_a, ctx_b, inst_space_a, inst_space_b,
          )
        }
        _ => Err("instance type mismatch")
      }
    (ComponentTypeRef::Module(_), ComponentTypeRef::Module(_)) => Ok(())
    (ComponentTypeRef::Component(_), ComponentTypeRef::Component(_)) => Ok(())
    _ => Err("type ref mismatch")
  }
}

///|
fn check_plug_import_export_type(
  socket_detail : ComponentDetail,
  plug_detail : ComponentDetail,
  socket_import : ComponentImportDetail,
  plug_export : ComponentExportDetail,
) -> Result[Unit, String] {
  if socket_import.kind != plug_export.kind {
    return Err("extern kind mismatch")
  }
  let socket_ctx = {
    detail: socket_detail,
    global_space: build_global_space(socket_detail.types),
    instance_cache: {},
  }
  let plug_ctx = {
    detail: plug_detail,
    global_space: build_global_space(plug_detail.types),
    instance_cache: {},
  }
  match plug_export.type_ref {
    Some(type_ref) => {
      let type_map : Map[String, String] = {}
      let res_map : Map[String, String] = {}
      let visiting : Map[String, Bool] = {}
      check_type_ref(
        socket_import.type_ref,
        type_ref,
        socket_ctx,
        plug_ctx,
        socket_ctx.global_space,
        plug_ctx.global_space,
        type_map,
        res_map,
        visiting,
      )
    }
    None =>
      match (socket_import.type_ref, plug_export.kind) {
        (ComponentTypeRef::Instance(inst_idx), ExternKind::Instance) =>
          match resolve_entry(socket_ctx, socket_ctx.global_space, inst_idx) {
            Some((ComponentTypeDef::Instance(inst_a), space_a)) => {
              let inst_space_a = build_instance_space(inst_a.entries, space_a)
              match
                resolve_instance_exports_from_instance_index(
                  plug_ctx.detail,
                  plug_export.index,
                  plug_ctx.global_space,
                ) {
                Ok(inst_b) => {
                  let inst_def_b = {
                    exports: inst_b.exports,
                    entries: inst_b.space.entries,
                  }
                  check_instance_type(
                    inst_a,
                    inst_def_b,
                    socket_ctx,
                    plug_ctx,
                    inst_space_a,
                    inst_b.space,
                  )
                }
                Err(e) => Err(e)
              }
            }
            _ => Ok(())
          }
        _ => Ok(())
      }
  }
}

///|
fn check_func_signature(
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
fn check_interface(
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

///|
/// Check whether a component's import/export surface matches the WIT world.
pub fn check_component_targets(
  component_bytes : Bytes,
  wit_input : @wit.ResolveInput,
) -> Result[Unit, String] {
  let detail = match parse_component_detail(component_bytes) {
    Ok(v) => v
    Err(e) => return Err("parse error: " + e.to_string())
  }
  let errors : Array[String] = []
  let comp_imports = build_import_map(detail.imports, errors)
  let comp_exports = build_export_map(detail.exports, errors)
  let matched_imports : Map[String, Bool] = {}
  let matched_exports : Map[String, Bool] = {}
  let global_space = build_global_space(detail.types)
  let instance_cache : Map[UInt, InstanceExportSet] = {}
  let ctx = { detail, global_space, instance_cache }
  let world = world_of(wit_input)
  let world_imports = collect_world_candidates(world.imports, wit_input.resolve)
  let world_exports = collect_world_candidates(world.exports, wit_input.resolve)
  for cand in world_imports {
    match find_import_by_names(comp_imports, cand.names) {
      Some((name, imp)) => {
        matched_imports.set(name, true)
        if imp.kind != cand.kind {
          errors.push(
            "import kind mismatch for `\{name}`: \{imp.kind.to_string()} vs \{cand.kind.to_string()}",
          )
        } else {
          match cand.item {
            @wit.RWorldItem::Function(func) =>
              match
                resolve_func_type_in_space(ctx, global_space, imp.type_ref) {
                Some(resolved) =>
                  match
                    check_func_signature(
                      name,
                      func,
                      resolved,
                      wit_input.resolve,
                      ctx,
                    ) {
                    Ok(_) => ()
                    Err(e) => errors.push("import func `\{name}`: " + e)
                  }
                None =>
                  errors.push("import func `\{name}`: not a function type")
              }
            @wit.RWorldItem::Interface(iface_ref) => {
              let iface = wit_input.resolve.interfaces[iface_ref.id]
              match
                resolve_instance_exports_from_type_ref(
                  detail,
                  imp.type_ref,
                  global_space,
                ) {
                Ok(export_set) =>
                  check_interface(
                    iface,
                    export_set,
                    wit_input.resolve,
                    ctx,
                    "import interface `\{name}`",
                    errors,
                  )
                Err(e) => errors.push("import interface `\{name}`: " + e)
              }
            }
            @wit.RWorldItem::Type(_) => ()
          }
        }
      }
      None =>
        if cand.names.length() > 0 {
          errors.push("import missing: `\{cand.names[0]}`")
        }
    }
  }
  for name, _ in comp_imports {
    if not(matched_imports.contains(name)) {
      errors.push("import extra: `\{name}`")
    }
  }
  for cand in world_exports {
    match find_export_by_names(comp_exports, cand.names) {
      Some((name, exp)) => {
        matched_exports.set(name, true)
        if exp.kind != cand.kind {
          errors.push(
            "export kind mismatch for `\{name}`: \{exp.kind.to_string()} vs \{cand.kind.to_string()}",
          )
        } else {
          match cand.item {
            @wit.RWorldItem::Function(func) =>
              match exp.type_ref {
                Some(type_ref) =>
                  match
                    resolve_func_type_in_space(ctx, global_space, type_ref) {
                    Some(resolved) =>
                      match
                        check_func_signature(
                          name,
                          func,
                          resolved,
                          wit_input.resolve,
                          ctx,
                        ) {
                        Ok(_) => ()
                        Err(e) => errors.push("export func `\{name}`: " + e)
                      }
                    None =>
                      errors.push("export func `\{name}`: not a function type")
                  }
                None => errors.push("export func `\{name}`: missing type")
              }
            @wit.RWorldItem::Interface(iface_ref) => {
              let iface = wit_input.resolve.interfaces[iface_ref.id]
              let exports = match exp.type_ref {
                Some(type_ref) =>
                  resolve_instance_exports_from_type_ref(
                    detail, type_ref, global_space,
                  )
                None =>
                  resolve_instance_exports_from_instance_index(
                    detail,
                    exp.index,
                    global_space,
                  )
              }
              match exports {
                Ok(export_set) =>
                  check_interface(
                    iface,
                    export_set,
                    wit_input.resolve,
                    ctx,
                    "export interface `\{name}`",
                    errors,
                  )
                Err(e) => errors.push("export interface `\{name}`: " + e)
              }
            }
            @wit.RWorldItem::Type(_) => ()
          }
        }
      }
      None =>
        if cand.names.length() > 0 {
          errors.push("export missing: `\{cand.names[0]}`")
        }
    }
  }
  for name, _ in comp_exports {
    if not(matched_exports.contains(name)) {
      errors.push("export extra: `\{name}`")
    }
  }
  if errors.length() > 0 {
    Err(errors.join("\n"))
  } else {
    Ok(())
  }
}

///|
test "resolve instance alias export" {
  let def = ComponentTypeDef::Defined(
    ComponentValType::Primitive(PrimitiveType::U32),
  )
  let detail = {
    types: [def],
    imports: [],
    exports: [],
    components: [],
    instances: [],
    imported_components: [],
    imported_instances: [],
  }
  let global_space = build_global_space(detail.types)
  let instance_cache : Map[UInt, InstanceExportSet] = {}
  let name : Bytes = b"foo"
  let export_set = {
    exports: [{ name, type_ref: ComponentTypeRef::Type(TypeBounds::Eq(0U)) }],
    space: global_space,
  }
  instance_cache.set(0U, export_set)
  let ctx = { detail, global_space, instance_cache }
  let local_space = build_instance_space(
    [InstanceTypeEntry::Alias(InstanceAliasTarget::Export(0U, name))],
    global_space,
  )
  match resolve_entry(ctx, local_space, 0U) {
    Some(
      (
        ComponentTypeDef::Defined(
          ComponentValType::Primitive(PrimitiveType::U32)
        ),
        _,
      )
    ) => ()
    _ => fail("expected alias export to resolve")
  }
}

///|
test "resolve instance alias outer" {
  let def = ComponentTypeDef::Defined(
    ComponentValType::Primitive(PrimitiveType::U32),
  )
  let detail = {
    types: [def],
    imports: [],
    exports: [],
    components: [],
    instances: [],
    imported_components: [],
    imported_instances: [],
  }
  let global_space = build_global_space(detail.types)
  let instance_cache : Map[UInt, InstanceExportSet] = {}
  let ctx = { detail, global_space, instance_cache }
  let local_space = build_instance_space(
    [InstanceTypeEntry::Alias(InstanceAliasTarget::Outer(0U, 0U))],
    global_space,
  )
  match resolve_entry(ctx, local_space, 0U) {
    Some(
      (
        ComponentTypeDef::Defined(
          ComponentValType::Primitive(PrimitiveType::U32)
        ),
        _,
      )
    ) => ()
    _ => fail("expected alias outer to resolve")
  }
}
