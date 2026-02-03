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
