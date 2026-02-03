///|
suberror PlugError {
  Parse(ParseError)
  Unsupported(String)
  NoPlugHappened
} derive(Show)

///|
priv struct PlugExportRef {
  plug_idx : Int
  name : Bytes
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
priv struct IndexState {
  mut func : UInt
  mut value : UInt
  mut type_ : UInt
  mut component : UInt
  mut instance : UInt
  mut core_module : UInt
}

///|
fn IndexState::new() -> IndexState {
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
fn IndexState::next(self : IndexState, kind : ExternKind) -> UInt {
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
fn match_plug_export(
  name : Bytes,
  kind : ExternKind,
  plugs : Array[Array[ExportInfo]],
) -> PlugExportRef? {
  for plug_idx in 0..<plugs.length() {
    let exports = plugs[plug_idx]
    for exp in exports {
      if exp.kind == kind && bytes_eq(exp.name, name) {
        return Some({ plug_idx, name: exp.name })
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
/// Compose a socket component with plug components.
pub fn plug_components(
  socket_bytes : Bytes,
  plug_bytes : Array[Bytes],
) -> Result[Bytes, PlugError] {
  let socket_info = match parse_info(socket_bytes) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let plug_infos : Array[ComponentInfo] = []
  for plug in plug_bytes {
    let info = match parse_info(plug) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    if info.imports.length() > 0 {
      return Err(
        PlugError::Unsupported(
          "plug component has imports; not supported in moon-component plug",
        ),
      )
    }
    plug_infos.push(info)
  }
  let plug_exports : Array[Array[ExportInfo]] = []
  for info in plug_infos {
    plug_exports.push(info.exports)
  }
  let forwarded : Array[ImportInfo] = []
  let plans : Array[ImportPlan] = []
  let mut used_plug = false
  for imp in socket_info.imports {
    if not(is_supported_kind(imp.kind)) {
      return Err(fail_unsupported(imp.name, imp.kind))
    }
    match match_plug_export(imp.name, imp.kind, plug_exports) {
      Some(found) => {
        plans.push({ name: imp.name, kind: imp.kind, source: Plug(found) })
        used_plug = true
      }
      None => {
        let idx = forwarded.length()
        forwarded.push(imp)
        plans.push({ name: imp.name, kind: imp.kind, source: Forwarded(idx) })
      }
    }
  }
  if not(used_plug) {
    return Err(PlugError::NoPlugHappened)
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

  // Component indices (plugs first, socket last)
  let plug_component_indices : Array[UInt] = []
  for _ in plug_bytes {
    plug_component_indices.push(index_state.next(ExternKind::Component))
  }
  let socket_component_idx = index_state.next(ExternKind::Component)

  // Import indices
  let forwarded_indices : Array[UInt] = Array::make(forwarded.length(), 0U)
  for i in 0..<forwarded.length() {
    let imp = forwarded[i]
    forwarded_indices[i] = index_state.next(imp.kind)
  }

  // Plug instance indices
  let plug_instance_indices : Array[UInt] = []
  for _ in plug_bytes {
    plug_instance_indices.push(index_state.next(ExternKind::Instance))
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

  // Section 4: component (plugs + socket)
  for plug in plug_bytes {
    push_section(out, 4U, plug.to_array())
  }
  push_section(out, 4U, socket_bytes.to_array())

  // Section 10: imports (forwarded)
  if forwarded.length() > 0 {
    let payload : Array[Byte] = []
    append_bytes(
      payload,
      encode_u32_leb128(forwarded.length().reinterpret_as_uint()),
    )
    for imp in forwarded {
      append_bytes(payload, encode_import(imp))
    }
    push_section(out, 10U, payload)
  }

  // Section 5: instances (plugs)
  if plug_bytes.length() > 0 {
    let payload : Array[Byte] = []
    append_bytes(
      payload,
      encode_u32_leb128(plug_bytes.length().reinterpret_as_uint()),
    )
    for i in 0..<plug_bytes.length() {
      let comp_idx = plug_component_indices[i]
      let inst_bytes = encode_instance(comp_idx, [])
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
        let inst_idx = plug_instance_indices[plug_ref.plug_idx]
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
