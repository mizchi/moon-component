///|
/// Minimal component-model types for parsing imports/exports
pub(all) enum PrimitiveType {
  Bool
  S8
  U8
  S16
  U16
  S32
  U32
  S64
  U64
  F32
  F64
  Char
  String
} derive(Show, Eq)

///|
pub(all) enum ComponentValType {
  Primitive(PrimitiveType)
  TypeIndex(UInt)
  List(ComponentValType)
  Map(ComponentValType, ComponentValType)
  Record(Array[RecordField])
  Variant(Array[VariantCase])
  Tuple(Array[ComponentValType])
  Flags(Array[Bytes])
  Enum(Array[Bytes])
  Option(ComponentValType)
  Result(ComponentValType?, ComponentValType?)
  Own(UInt)
  Borrow(UInt)
  ErrorContext
  Future(ComponentValType?)
  Stream(ComponentValType?)
  FixedSizeList(ComponentValType, UInt)
} derive(Show, Eq)

///|
pub(all) struct RecordField {
  name : Bytes
  type_ : ComponentValType
} derive(Show, Eq)

///|
pub(all) struct VariantCase {
  name : Bytes
  type_ : ComponentValType?
  refines : UInt?
} derive(Show, Eq)

///|
pub(all) struct ComponentParam {
  name : Bytes
  type_ : ComponentValType
} derive(Show, Eq)

///|
pub(all) struct ComponentResult {
  name : Bytes?
  type_ : ComponentValType
} derive(Show, Eq)

///|
pub(all) struct ComponentFuncType {
  params : Array[ComponentParam]
  results : Array[ComponentResult]
} derive(Show, Eq)

///|
pub(all) enum TypeBounds {
  Eq(UInt)
  SubResource
} derive(Show, Eq)

///|
pub(all) enum ComponentExternDesc {
  Module(UInt)
  Func(UInt)
  Value(ComponentValType)
  Type(TypeBounds)
  Component(UInt)
  Instance(UInt)
} derive(Show, Eq)

///|
/// Simplified extern kind used by plug logic
pub(all) enum ExternKind {
  CoreModule
  Func
  Value
  Type
  Component
  Instance
} derive(Show, Eq)

///|
pub(all) enum ComponentTypeRef {
  Module(UInt)
  Func(UInt)
  Value(ComponentValType)
  Type(TypeBounds)
  Component(UInt)
  Instance(UInt)
} derive(Show, Eq)

///|
pub(all) struct ImportInfo {
  name : Bytes
  kind : ExternKind
  raw_desc : Bytes
} derive(Show, Eq)

///|
pub(all) struct ComponentImportDetail {
  name : Bytes
  kind : ExternKind
  type_ref : ComponentTypeRef
} derive(Show, Eq)

///|
pub(all) struct ExportInfo {
  name : Bytes
  kind : ExternKind
} derive(Show, Eq)

///|
pub(all) struct ComponentExportDetail {
  name : Bytes
  kind : ExternKind
  index : UInt
  type_ref : ComponentTypeRef?
} derive(Show, Eq)

///|
pub(all) struct ComponentInfo {
  imports : Array[ImportInfo]
  exports : Array[ExportInfo]
} derive(Show, Eq)

///|
pub(all) struct InstanceExport {
  name : Bytes
  type_ref : ComponentTypeRef
} derive(Show, Eq)

///|
pub(all) enum ComponentTypeDef {
  Defined(ComponentValType)
  Func(ComponentFuncType)
  Instance(InstanceTypeDef)
  Resource
  Component(ComponentTypeDetail)
} derive(Show, Eq)

///|
pub(all) struct ComponentTypeDetail {
  exports : Array[InstanceExport]
  entries : Array[InstanceTypeEntry]
  core_types : Array[CoreTypeRaw]
} derive(Show, Eq)

///|
pub(all) enum CoreTypeKind {
  Module
  Other
} derive(Show, Eq)

///|
pub(all) struct CoreTypeRaw {
  kind : CoreTypeKind
  raw : Bytes
} derive(Show, Eq)

///|
pub(all) enum InstanceTypeEntry {
  Local(ComponentTypeDef)
  Alias(InstanceAliasTarget)
} derive(Show, Eq)

///|
pub(all) enum InstanceAliasTarget {
  Outer(UInt, UInt)
  Export(UInt, Bytes)
  Unknown
} derive(Show, Eq)

///|
pub(all) struct InstanceTypeDef {
  exports : Array[InstanceExport]
  entries : Array[InstanceTypeEntry]
} derive(Show, Eq)

///|
pub(all) enum ComponentInstanceDef {
  Instantiate(UInt)
  FromExports(Array[ExportInfo])
} derive(Show, Eq)

///|
pub(all) struct ComponentDetail {
  types : Array[ComponentTypeDef]
  imports : Array[ComponentImportDetail]
  exports : Array[ComponentExportDetail]
  components : Array[Bytes]
  instances : Array[ComponentInstanceDef]
  imported_components : Array[ComponentTypeRef]
  imported_instances : Array[ComponentTypeRef]
  core_modules : Array[Bytes]
  core_types : Array[CoreTypeRaw]
} derive(Show, Eq)
