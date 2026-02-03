///|
suberror PlugError {
  Parse(ParseError)
  Unsupported(String)
  TypeMismatch(String)
  NoPlugHappened
} derive(Show)

///|
priv struct PlugExportRef {
  plug_idx : Int
  name : Bytes
  export_index : Int
}

///|
priv struct ImportPlan {
  name : Bytes
  kind : ExternKind
  source : ImportSource
}

///|
priv enum ImportSource {
  Plug(PlugExportRef)
  Forwarded(Int) // index in forwarded imports list
}

///|
pub struct IndexState {
  mut func : UInt
  mut value : UInt
  mut type_ : UInt
  mut component : UInt
  mut instance : UInt
  mut core_module : UInt
}

///|
pub fn IndexState::new() -> IndexState {
  {
    func: 0U,
    value: 0U,
    type_: 0U,
    component: 0U,
    instance: 0U,
    core_module: 0U,
  }
}

///|
pub fn IndexState::next(self : IndexState, kind : ExternKind) -> UInt {
  match kind {
    Func => {
      let idx = self.func
      self.func = self.func + 1U
      idx
    }
    Value => {
      let idx = self.value
      self.value = self.value + 1U
      idx
    }
    Type => {
      let idx = self.type_
      self.type_ = self.type_ + 1U
      idx
    }
    Component => {
      let idx = self.component
      self.component = self.component + 1U
      idx
    }
    Instance => {
      let idx = self.instance
      self.instance = self.instance + 1U
      idx
    }
    CoreModule => {
      let idx = self.core_module
      self.core_module = self.core_module + 1U
      idx
    }
  }
}

///|
fn is_supported_kind(_kind : ExternKind) -> Bool {
  true
}

///|
fn bytes_eq(a : Bytes, b : Bytes) -> Bool {
  a == b
}

///|
fn build_import_detail_map(
  detail : ComponentDetail,
) -> Map[String, ComponentImportDetail] {
  let map : Map[String, ComponentImportDetail] = {}
  for imp in detail.imports {
    map.set(imp.name.to_string(), imp)
  }
  map
}

///|
fn merge_import_info(
  merged : Array[ImportInfo],
  merged_details : Array[ComponentImportDetail],
  merged_sources : Array[ComponentDetail],
  index_map : Map[String, UInt],
  info : ImportInfo,
  detail : ComponentImportDetail,
  source_detail : ComponentDetail,
  best_effort : Bool,
) -> Result[UInt, PlugError] {
  let key = info.name.to_string()
  match index_map.get(key) {
    Some(idx) => {
      let existing_detail = merged_details[idx.reinterpret_as_int()]
      let existing_source = merged_sources[idx.reinterpret_as_int()]
      match
        compare_import_types(
          existing_source,
          existing_detail,
          source_detail,
          detail,
          best_effort~,
        ) {
        Ok(ImportRelation::Equal) => Ok(idx)
        Ok(ImportRelation::BSubtypeA) => Ok(idx)
        Ok(ImportRelation::ASubtypeB) => {
          merged[idx.reinterpret_as_int()] = info
          merged_details[idx.reinterpret_as_int()] = detail
          merged_sources[idx.reinterpret_as_int()] = source_detail
          Ok(idx)
        }
        Err(msg) =>
          Err(
            PlugError::TypeMismatch(
              "import type conflict for `\{info.name.to_string()}`: " + msg,
            ),
          )
      }
    }
    None => {
      let idx = merged.length().reinterpret_as_uint()
      merged.push(info)
      merged_details.push(detail)
      merged_sources.push(source_detail)
      index_map.set(key, idx)
      Ok(idx)
    }
  }
}

///|
fn match_plug_export(
  name : Bytes,
  kind : ExternKind,
  plugs : Array[Array[ExportInfo]],
) -> PlugExportRef? {
  for plug_idx in 0..<plugs.length() {
    let exports = plugs[plug_idx]
    for export_index in 0..<exports.length() {
      let exp = exports[export_index]
      if exp.kind == kind && bytes_eq(exp.name, name) {
        return Some({ plug_idx, name: exp.name, export_index })
      }
    }
  }
  None
}

///|
fn fail_unsupported(name : Bytes, kind : ExternKind) -> PlugError {
  PlugError::Unsupported(
    "unsupported import kind for `\{name.to_string()}`: \{kind.to_string()}",
  )
}

///|
fn parse_info(bytes : Bytes) -> Result[ComponentInfo, PlugError] {
  match parse_component_info(bytes) {
    Ok(v) => Ok(v)
    Err(e) => Err(PlugError::Parse(e))
  }
}

///|
fn parse_detail(bytes : Bytes) -> Result[ComponentDetail, PlugError] {
  match parse_component_detail(bytes) {
    Ok(v) => Ok(v)
    Err(e) => Err(PlugError::Parse(e))
  }
}

///|
/// Compose a socket component with plug components.
pub fn plug_components(
  socket_bytes : Bytes,
  plug_bytes : Array[Bytes],
  best_effort? : Bool = false,
) -> Result[Bytes, PlugError] {
  let socket_info = match parse_info(socket_bytes) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let socket_detail = match parse_detail(socket_bytes) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let plug_infos : Array[ComponentInfo] = []
  let plug_details : Array[ComponentDetail] = []
  for plug in plug_bytes {
    let info = match parse_info(plug) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    let detail = match parse_detail(plug) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    plug_infos.push(info)
    plug_details.push(detail)
  }
  let plug_exports : Array[Array[ExportInfo]] = []
  for info in plug_infos {
    plug_exports.push(info.exports)
  }
  let socket_import_detail_map = build_import_detail_map(socket_detail)
  let plug_import_detail_maps : Array[Map[String, ComponentImportDetail]] = []
  for detail in plug_details {
    plug_import_detail_maps.push(build_import_detail_map(detail))
  }
  let forwarded_imports : Array[ImportInfo] = []
  let forwarded_details : Array[ComponentImportDetail] = []
  let plans : Array[ImportPlan] = []
  let used_plug_flags : Array[Bool] = Array::make(plug_infos.length(), false)
  let mut used_plug = false
  for imp in socket_info.imports {
    if not(is_supported_kind(imp.kind)) {
      return Err(fail_unsupported(imp.name, imp.kind))
    }
    match match_plug_export(imp.name, imp.kind, plug_exports) {
      Some(found) => {
        plans.push({ name: imp.name, kind: imp.kind, source: Plug(found) })
        used_plug = true
        used_plug_flags[found.plug_idx] = true
      }
      None => {
        let detail = match socket_import_detail_map.get(imp.name.to_string()) {
          Some(d) => d
          None =>
            return Err(
              PlugError::TypeMismatch(
                "missing socket import detail for `\{imp.name.to_string()}`",
              ),
            )
        }
        let idx = forwarded_imports.length()
        forwarded_imports.push(imp)
        forwarded_details.push(detail)
        plans.push({ name: imp.name, kind: imp.kind, source: Forwarded(idx) })
      }
    }
  }
  if not(used_plug) {
    return Err(PlugError::NoPlugHappened)
  }
  let merged_imports : Array[ImportInfo] = []
  let merged_details : Array[ComponentImportDetail] = []
  let merged_sources : Array[ComponentDetail] = []
  let import_index_map : Map[String, UInt] = {}
  let forwarded_indices : Array[UInt] = Array::make(
    forwarded_imports.length(),
    0U,
  )
  for i in 0..<forwarded_imports.length() {
    let merged_idx = match
      merge_import_info(
        merged_imports,
        merged_details,
        merged_sources,
        import_index_map,
        forwarded_imports[i],
        forwarded_details[i],
        socket_detail,
        best_effort,
      ) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    forwarded_indices[i] = merged_idx
  }
  let plug_import_indices : Array[Array[UInt]] = []
  for plug_idx in 0..<plug_infos.length() {
    let imports = plug_infos[plug_idx].imports
    let indices : Array[UInt] = Array::make(imports.length(), 0U)
    if used_plug_flags[plug_idx] {
      let detail_map = plug_import_detail_maps[plug_idx]
      let plug_detail = plug_details[plug_idx]
      for i in 0..<imports.length() {
        let imp = imports[i]
        let detail = match detail_map.get(imp.name.to_string()) {
          Some(d) => d
          None =>
            return Err(
              PlugError::TypeMismatch(
                "missing plug import detail for `\{imp.name.to_string()}`",
              ),
            )
        }
        let merged_idx = match
          merge_import_info(
            merged_imports, merged_details, merged_sources, import_index_map, imp,
            detail, plug_detail, best_effort,
          ) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        indices[i] = merged_idx
      }
    }
    plug_import_indices.push(indices)
  }
  for i in 0..<plans.length() {
    match plans[i].source {
      Plug(plug_ref) => {
        let import_detail = socket_detail.imports[i]
        let plug_detail = plug_details[plug_ref.plug_idx]
        let export_detail = plug_detail.exports[plug_ref.export_index]
        match
          check_plug_import_export_type(
            socket_detail,
            plug_detail,
            import_detail,
            export_detail,
            best_effort~,
          ) {
          Ok(_) => ()
          Err(msg) =>
            return Err(
              PlugError::TypeMismatch(
                "import `\{import_detail.name.to_string()}` vs export `\{export_detail.name.to_string()}`: " +
                msg,
              ),
            )
        }
      }
      Forwarded(_) => ()
    }
  }

  // Validate that all exports used are supported
  for exp in socket_info.exports {
    if not(is_supported_kind(exp.kind)) {
      return Err(
        PlugError::Unsupported(
          "unsupported export kind for `\{exp.name.to_string()}`: \{exp.kind.to_string()}",
        ),
      )
    }
  }
  let index_state = IndexState::new()

  // Component indices (used plugs first, socket last)
  let plug_component_indices : Array[UInt?] = Array::make(
    plug_bytes.length(),
    None,
  )
  for i in 0..<plug_bytes.length() {
    if used_plug_flags[i] {
      plug_component_indices[i] = Some(index_state.next(ExternKind::Component))
    }
  }
  let socket_component_idx = index_state.next(ExternKind::Component)

  // Import indices (merged)
  let merged_import_indices : Array[UInt] = Array::make(
    merged_imports.length(),
    0U,
  )
  for i in 0..<merged_imports.length() {
    let imp = merged_imports[i]
    merged_import_indices[i] = index_state.next(imp.kind)
  }
  for i in 0..<forwarded_indices.length() {
    let merged_idx = forwarded_indices[i].reinterpret_as_int()
    forwarded_indices[i] = merged_import_indices[merged_idx]
  }
  for plug_idx in 0..<plug_import_indices.length() {
    let indices = plug_import_indices[plug_idx]
    for i in 0..<indices.length() {
      let merged_idx = indices[i].reinterpret_as_int()
      indices[i] = merged_import_indices[merged_idx]
    }
  }

  // Plug instance indices
  let plug_instance_indices : Array[UInt?] = Array::make(
    plug_bytes.length(),
    None,
  )
  for i in 0..<plug_bytes.length() {
    if used_plug_flags[i] {
      plug_instance_indices[i] = Some(index_state.next(ExternKind::Instance))
    }
  }

  // Alias indices for plug exports used in socket imports
  let plan_alias_indices : Array[UInt?] = Array::make(plans.length(), None)
  for i in 0..<plans.length() {
    let plan = plans[i]
    match plan.source {
      Plug(_) => {
        let idx = index_state.next(plan.kind)
        plan_alias_indices[i] = Some(idx)
      }
      Forwarded(_) => ()
    }
  }

  // Socket instance index (after aliases)
  let socket_instance_idx = index_state.next(ExternKind::Instance)

  // Alias indices for socket exports
  let socket_export_alias_indices : Array[UInt] = []
  for exp in socket_info.exports {
    socket_export_alias_indices.push(index_state.next(exp.kind))
  }

  // Encode component
  let out : Array[Byte] = []
  append_bytes(out, [
    0x00U.to_byte(),
    0x61U.to_byte(),
    0x73U.to_byte(),
    0x6dU.to_byte(),
  ])
  append_bytes(out, [0x0dU.to_byte(), 0x00U.to_byte()])
  append_bytes(out, [0x01U.to_byte(), 0x00U.to_byte()])

  // Section 4: component (used plugs + socket)
  for i in 0..<plug_bytes.length() {
    if used_plug_flags[i] {
      let plug = plug_bytes[i]
      push_section(out, 4U, plug.to_array())
    }
  }
  push_section(out, 4U, socket_bytes.to_array())

  // Section 10: imports (forwarded + plug imports)
  if merged_imports.length() > 0 {
    let payload : Array[Byte] = []
    append_bytes(
      payload,
      encode_u32_leb128(merged_imports.length().reinterpret_as_uint()),
    )
    for imp in merged_imports {
      append_bytes(payload, encode_import(imp))
    }
    push_section(out, 10U, payload)
  }

  // Section 5: instances (plugs)
  let mut used_plug_count = 0
  for used in used_plug_flags {
    if used {
      used_plug_count = used_plug_count + 1
    }
  }
  if used_plug_count > 0 {
    let payload : Array[Byte] = []
    append_bytes(
      payload,
      encode_u32_leb128(used_plug_count.reinterpret_as_uint()),
    )
    for i in 0..<plug_bytes.length() {
      if not(used_plug_flags[i]) {
        continue
      }
      let comp_idx = match plug_component_indices[i] {
        Some(v) => v
        None =>
          return Err(
            PlugError::Unsupported(
              "missing plug component index for `\{i.to_string()}`",
            ),
          )
      }
      let args : Array[InstantiateArgEntry] = []
      let imports = plug_infos[i].imports
      let indices = plug_import_indices[i]
      for j in 0..<imports.length() {
        let imp = imports[j]
        args.push({ name: imp.name, kind: imp.kind, idx: indices[j] })
      }
      let inst_bytes = encode_instance(comp_idx, args)
      append_bytes(payload, inst_bytes)
    }
    push_section(out, 5U, payload)
  }

  // Section 6: aliases for plug exports
  let alias_payload : Array[Byte] = []
  let mut alias_count = 0
  for i in 0..<plans.length() {
    match plans[i].source {
      Plug(plug_ref) => {
        let inst_idx = match plug_instance_indices[plug_ref.plug_idx] {
          Some(v) => v
          None =>
            return Err(
              PlugError::Unsupported(
                "missing plug instance index for `\{plug_ref.name.to_string()}`",
              ),
            )
        }
        append_bytes(
          alias_payload,
          encode_alias(plans[i].kind, inst_idx, plug_ref.name),
        )
        alias_count = alias_count + 1
      }
      Forwarded(_) => ()
    }
  }
  if alias_count > 0 {
    let payload : Array[Byte] = []
    append_bytes(payload, encode_u32_leb128(alias_count.reinterpret_as_uint()))
    append_bytes(payload, alias_payload)
    push_section(out, 6U, payload)
  }

  // Section 5: instance (socket)
  let socket_payload : Array[Byte] = []
  append_bytes(socket_payload, encode_u32_leb128(1U))
  let args : Array[InstantiateArgEntry] = []
  for i in 0..<plans.length() {
    let plan = plans[i]
    match plan.source {
      Plug(_) =>
        match plan_alias_indices[i] {
          Some(idx) => args.push({ name: plan.name, kind: plan.kind, idx })
          None => ()
        }
      Forwarded(fwd_idx) => {
        let idx = forwarded_indices[fwd_idx]
        args.push({ name: plan.name, kind: plan.kind, idx })
      }
    }
  }
  append_bytes(socket_payload, encode_instance(socket_component_idx, args))
  push_section(out, 5U, socket_payload)

  // Section 6: aliases for socket exports
  let export_alias_payload : Array[Byte] = []
  let export_count = socket_info.exports.length()
  if export_count > 0 {
    for i in 0..<export_count {
      let exp = socket_info.exports[i]
      append_bytes(
        export_alias_payload,
        encode_alias(exp.kind, socket_instance_idx, exp.name),
      )
    }
    let payload : Array[Byte] = []
    append_bytes(payload, encode_u32_leb128(export_count.reinterpret_as_uint()))
    append_bytes(payload, export_alias_payload)
    push_section(out, 6U, payload)
  }

  // Section 11: exports
  if export_count > 0 {
    let payload : Array[Byte] = []
    append_bytes(payload, encode_u32_leb128(export_count.reinterpret_as_uint()))
    for i in 0..<export_count {
      let exp = socket_info.exports[i]
      let idx = socket_export_alias_indices[i]
      append_bytes(payload, encode_export(exp.name, exp.kind, idx))
    }
    push_section(out, 11U, payload)
  }
  Ok(Bytes::from_array(out))
}
