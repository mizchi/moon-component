///|
suberror WacParseError {
  Message(String)
} derive(Show)

///|
pub(all) struct WacDocument {
  pkg : String
  targets : String?
  stmts : Array[WacStmt]
} derive(Show, ToJson)

///|
pub(all) enum WacStmt {
  Let(String, WacExpr)
  Export(WacExport)
  Import(WacImport)
} derive(Show, ToJson)

///|
pub(all) struct WacName {
  value : String
  exact : Bool
} derive(Show, ToJson)

///|
pub(all) struct WacImport {
  local_name : String
  import_name : String
  ty : WacImportType
} derive(Show, ToJson)

///|
pub(all) enum WacImportType {
  Package(String)
  Ident(String)
  InlineInterface(String)
  InlineFunc(String)
} derive(Show, ToJson)

///|
pub(all) struct WacExport {
  expr : WacExpr
  all : Bool
  as_name : String?
} derive(Show, ToJson)

///|
pub(all) enum WacExpr {
  Name(String)
  Access(WacExpr, WacName)
  New(WacNew)
} derive(Show, ToJson)

///|
pub(all) struct WacNew {
  pkg : String
  args : Array[WacArg]
} derive(Show, ToJson)

///|
pub(all) enum WacArg {
  SpreadAll
  SpreadInstance(String)
  Named(WacName, WacExpr)
  Inferred(WacExpr)
} derive(Show, ToJson)

///|
pub(all) struct WacResolveSummary {
  pkg : String
  components : Array[String]
  instantiations : Array[WacInstantiationSummary]
  exports : Array[String]
  imports : Array[String]
} derive(Show, ToJson)

///|
pub(all) struct WacInstantiationSummary {
  name : String
  component : String
  args : Array[String]
} derive(Show, ToJson)

///|
priv struct WacParser {
  bytes : Bytes
  mut pos : Int
}

///|
fn WacParser::new(input : String) -> WacParser {
  { bytes: @utf8.encode(input), pos: 0 }
}

///|
fn is_space(b : Byte) -> Bool {
  match b {
    b' ' | b'\t' | b'\n' | b'\r' => true
    _ => false
  }
}

///|
fn is_ident_start(b : Byte) -> Bool {
  match b {
    b'a'..=b'z' | b'A'..=b'Z' | b'_' => true
    _ => false
  }
}

///|
fn is_ident_char(b : Byte) -> Bool {
  is_ident_start(b) || (b >= b'0' && b <= b'9') || b == b'-'
}

///|
fn is_pkg_char(b : Byte) -> Bool {
  is_ident_char(b) || b == b':' || b == b'/' || b == b'.'
}

///|
fn wac_bytes_to_string(bytes : Bytes) -> String raise WacParseError {
  @utf8.decode(bytes) catch {
    _ => raise WacParseError::Message("invalid utf-8")
  }
}

///|
fn WacParser::peek(self : WacParser) -> Byte? {
  if self.pos < self.bytes.length() {
    Some(self.bytes[self.pos])
  } else {
    None
  }
}

///|
fn WacParser::skip_ws(self : WacParser) -> Unit {
  while self.pos < self.bytes.length() {
    let b = self.bytes[self.pos]
    if is_space(b) {
      self.pos = self.pos + 1
      continue
    }
    if b == b'/' && self.pos + 1 < self.bytes.length() {
      let b2 = self.bytes[self.pos + 1]
      if b2 == b'/' {
        self.pos = self.pos + 2
        while self.pos < self.bytes.length() && self.bytes[self.pos] != b'\n' {
          self.pos = self.pos + 1
        }
        continue
      }
      if b2 == b'*' {
        self.pos = self.pos + 2
        while self.pos + 1 < self.bytes.length() {
          if self.bytes[self.pos] == b'*' && self.bytes[self.pos + 1] == b'/' {
            self.pos = self.pos + 2
            break
          }
          self.pos = self.pos + 1
        }
        continue
      }
    }
    break
  }
}

///|
fn WacParser::consume_char(self : WacParser, ch : Byte) -> Bool {
  self.skip_ws()
  match self.peek() {
    Some(b) if b == ch => {
      self.pos = self.pos + 1
      true
    }
    _ => false
  }
}

///|
fn WacParser::expect_char(
  self : WacParser,
  ch : Byte,
) -> Unit raise WacParseError {
  if not(self.consume_char(ch)) {
    raise WacParseError::Message(
      "expected `\{String::from_array([ch.to_char()])}`",
    )
  }
}

///|
fn WacParser::starts_with(self : WacParser, kw : String) -> Bool {
  let kw_bytes = @utf8.encode(kw)
  if self.pos + kw_bytes.length() > self.bytes.length() {
    return false
  }
  for i in 0..<kw_bytes.length() {
    if self.bytes[self.pos + i] != kw_bytes[i] {
      return false
    }
  }
  true
}

///|
fn WacParser::consume_keyword(self : WacParser, kw : String) -> Bool {
  self.skip_ws()
  if not(self.starts_with(kw)) {
    return false
  }
  let end_pos = self.pos + kw.length()
  let mut boundary_ok = true
  if end_pos < self.bytes.length() {
    let b = self.bytes[end_pos]
    if is_ident_char(b) {
      boundary_ok = false
    }
  }
  if not(boundary_ok) {
    return false
  }
  self.pos = end_pos
  true
}

///|
fn WacParser::parse_ident(self : WacParser) -> String raise WacParseError {
  self.skip_ws()
  let start = self.pos
  match self.peek() {
    Some(b) if is_ident_start(b) => ()
    _ => raise WacParseError::Message("expected identifier")
  }
  while self.pos < self.bytes.length() {
    let b = self.bytes[self.pos]
    if not(is_ident_char(b)) {
      break
    }
    self.pos = self.pos + 1
  }
  let slice = self.bytes[start:self.pos].to_bytes()
  wac_bytes_to_string(slice)
}

///|
fn WacParser::parse_string_literal(
  self : WacParser,
) -> String raise WacParseError {
  self.skip_ws()
  if not(self.consume_char(b'"')) {
    raise WacParseError::Message("expected string literal")
  }
  let out : Array[Byte] = []
  while true {
    if self.pos >= self.bytes.length() {
      raise WacParseError::Message("unterminated string literal")
    }
    let b = self.bytes[self.pos]
    self.pos = self.pos + 1
    if b == b'"' {
      break
    }
    if b == b'\\' {
      if self.pos >= self.bytes.length() {
        raise WacParseError::Message("unterminated string escape")
      }
      let esc = self.bytes[self.pos]
      self.pos = self.pos + 1
      let mapped = match esc {
        b'\\' => b'\\'
        b'"' => b'"'
        b'n' => b'\n'
        b'r' => b'\r'
        b't' => b'\t'
        _ => raise WacParseError::Message("unknown escape sequence")
      }
      out.push(mapped)
    } else {
      out.push(b)
    }
  }
  wac_bytes_to_string(Bytes::from_array(out))
}

///|
fn WacParser::skip_string(self : WacParser) -> Unit raise WacParseError {
  if not(self.consume_char(b'"')) {
    raise WacParseError::Message("expected string")
  }
  while true {
    if self.pos >= self.bytes.length() {
      raise WacParseError::Message("unterminated string")
    }
    let b = self.bytes[self.pos]
    self.pos = self.pos + 1
    if b == b'"' {
      break
    }
    if b == b'\\' {
      if self.pos >= self.bytes.length() {
        raise WacParseError::Message("unterminated string escape")
      }
      self.pos = self.pos + 1
    }
  }
}

///|
fn WacParser::parse_brace_block(self : WacParser) -> String raise WacParseError {
  self.skip_ws()
  if not(self.consume_char(b'{')) {
    raise WacParseError::Message("expected '{'")
  }
  let start = self.pos - 1
  let mut depth = 1
  while depth > 0 {
    if self.pos >= self.bytes.length() {
      raise WacParseError::Message("unterminated '{'")
    }
    let b = self.bytes[self.pos]
    if b == b'"' {
      self.skip_string()
      continue
    }
    self.pos = self.pos + 1
    if b == b'{' {
      depth = depth + 1
    } else if b == b'}' {
      depth = depth - 1
    }
  }
  let end = self.pos
  wac_bytes_to_string(self.bytes[start:end].to_bytes())
}

///|
fn WacParser::parse_until_semicolon(
  self : WacParser,
) -> String raise WacParseError {
  let start = self.pos
  let mut paren = 0
  let mut bracket = 0
  let mut brace = 0
  while self.pos < self.bytes.length() {
    let b = self.bytes[self.pos]
    if b == b'"' {
      self.skip_string()
      continue
    }
    if paren == 0 && bracket == 0 && brace == 0 && b == b';' {
      break
    }
    self.pos = self.pos + 1
    if b == b'(' {
      paren = paren + 1
    } else if b == b')' {
      paren = paren - 1
    } else if b == b'[' {
      bracket = bracket + 1
    } else if b == b']' {
      bracket = bracket - 1
    } else if b == b'{' {
      brace = brace + 1
    } else if b == b'}' {
      brace = brace - 1
    }
  }
  if self.pos >= self.bytes.length() {
    raise WacParseError::Message("unterminated inline type")
  }
  wac_bytes_to_string(self.bytes[start:self.pos].to_bytes())
}

///|
fn WacParser::parse_import_type(
  self : WacParser,
) -> WacImportType raise WacParseError {
  self.skip_ws()
  if self.starts_with("interface") {
    let _ = self.consume_keyword("interface")
    let body = self.parse_brace_block()
    return WacImportType::InlineInterface(body)
  }
  if self.starts_with("func") {
    let _ = self.consume_keyword("func")
    let sig = self.parse_until_semicolon()
    return WacImportType::InlineFunc("func" + sig)
  }
  match self.peek() {
    Some(b) if b == b'"' => WacImportType::Package(self.parse_string_literal())
    _ => {
      let name = self.parse_package()
      if name.contains("/") || name.contains(":") {
        WacImportType::Package(name)
      } else {
        WacImportType::Ident(name)
      }
    }
  }
}

///|
fn WacParser::parse_name_or_string(
  self : WacParser,
) -> WacName raise WacParseError {
  self.skip_ws()
  match self.peek() {
    Some(b) if b == b'"' => {
      let value = self.parse_string_literal()
      { value, exact: true }
    }
    _ => {
      let value = self.parse_ident()
      { value, exact: false }
    }
  }
}

///|
fn WacParser::parse_package(self : WacParser) -> String raise WacParseError {
  self.skip_ws()
  let start = self.pos
  match self.peek() {
    Some(b) if is_ident_start(b) => ()
    _ => raise WacParseError::Message("expected package name")
  }
  while self.pos < self.bytes.length() {
    let b = self.bytes[self.pos]
    if not(is_pkg_char(b)) {
      break
    }
    self.pos = self.pos + 1
  }
  let slice = self.bytes[start:self.pos].to_bytes()
  wac_bytes_to_string(slice)
}

///|
fn WacParser::consume_dots(self : WacParser) -> Bool {
  self.skip_ws()
  if self.pos + 2 >= self.bytes.length() {
    return false
  }
  if self.bytes[self.pos] == b'.' &&
    self.bytes[self.pos + 1] == b'.' &&
    self.bytes[self.pos + 2] == b'.' {
    self.pos = self.pos + 3
    return true
  }
  false
}

///|
fn WacParser::parse_expr(self : WacParser) -> WacExpr raise WacParseError {
  self.skip_ws()
  if self.consume_keyword("new") {
    let pkg = self.parse_package()
    self.expect_char(b'{')
    let args : Array[WacArg] = []
    while true {
      self.skip_ws()
      if self.consume_char(b'}') {
        break
      }
      if self.consume_dots() {
        self.skip_ws()
        match self.peek() {
          Some(b) if is_ident_start(b) => {
            let name = self.parse_ident()
            args.push(WacArg::SpreadInstance(name))
          }
          _ => args.push(WacArg::SpreadAll)
        }
      } else {
        let name = self.parse_name_or_string()
        self.skip_ws()
        if name.exact {
          if not(self.consume_char(b':')) {
            raise WacParseError::Message("expected ':' after string argument")
          }
          let value = self.parse_expr()
          args.push(WacArg::Named(name, value))
        } else if self.consume_char(b':') {
          let value = self.parse_expr()
          args.push(WacArg::Named(name, value))
        } else {
          let mut expr : WacExpr = WacExpr::Name(name.value)
          expr = self.parse_access_tail(expr)
          args.push(WacArg::Inferred(expr))
        }
      }
      self.skip_ws()
      let _ = self.consume_char(b',')

    }
    return WacExpr::New({ pkg, args })
  }
  if self.consume_char(b'(') {
    let inner = self.parse_expr()
    self.expect_char(b')')
    return self.parse_access_tail(inner)
  }
  let name = self.parse_ident()
  let expr = WacExpr::Name(name)
  self.parse_access_tail(expr)
}

///|
fn WacParser::parse_access_tail(
  self : WacParser,
  expr : WacExpr,
) -> WacExpr raise WacParseError {
  let mut cur = expr
  while true {
    self.skip_ws()
    if self.starts_with("...") {
      break
    }
    if self.consume_char(b'.') {
      let name = self.parse_ident()
      cur = WacExpr::Access(cur, { value: name, exact: false })
      continue
    }
    if self.consume_char(b'[') {
      let name = self.parse_string_literal()
      self.expect_char(b']')
      cur = WacExpr::Access(cur, { value: name, exact: true })
      continue
    }
    break
  }
  cur
}

///|
fn WacParser::parse_stmt(self : WacParser) -> WacStmt raise WacParseError {
  if self.consume_keyword("let") {
    let name = self.parse_ident()
    self.expect_char(b'=')
    let expr = self.parse_expr()
    self.expect_char(b';')
    return WacStmt::Let(name, expr)
  }
  if self.consume_keyword("export") {
    let expr = self.parse_expr()
    let all = self.consume_dots()
    let mut as_name : String? = None
    if self.consume_keyword("as") {
      let name = self.parse_name_or_string()
      as_name = Some(name.value)
    }
    if all && as_name is Some(_) {
      raise WacParseError::Message("export ... cannot have alias")
    }
    self.expect_char(b';')
    return WacStmt::Export({ expr, all, as_name })
  }
  if self.consume_keyword("import") {
    let local_name = self.parse_ident()
    let mut import_name : String? = None
    if self.consume_keyword("as") {
      let name = self.parse_name_or_string()
      import_name = Some(name.value)
    }
    self.expect_char(b':')
    let ty = self.parse_import_type()
    let (default_name, ty) = import_type_default_name(
      ty,
      local_name.to_string(),
    )
    let name = match import_name {
      Some(n) => n
      None => default_name
    }
    self.expect_char(b';')
    return WacStmt::Import({ local_name, import_name: name, ty })
  }
  raise WacParseError::Message("unknown statement")
}

///|
pub fn parse_wac(source : String) -> Result[WacDocument, WacParseError] {
  let parser = WacParser::new(source)
  parser.skip_ws()
  if not(parser.consume_keyword("package")) {
    return Err(WacParseError::Message("missing package directive"))
  }
  let pkg = parser.parse_package() catch { e => return Err(e) }
  let mut targets : String? = None
  parser.skip_ws()
  if parser.consume_keyword("targets") {
    let target = match parser.peek() {
      Some(b) if b == b'"' =>
        parser.parse_string_literal() catch {
          e => return Err(e)
        }
      _ => parser.parse_package() catch { e => return Err(e) }
    }
    targets = Some(target)
  }
  parser.expect_char(b';') catch {
    e => return Err(e)
  }
  let stmts : Array[WacStmt] = []
  while true {
    parser.skip_ws()
    if parser.pos >= parser.bytes.length() {
      break
    }
    let stmt = parser.parse_stmt() catch { e => return Err(e) }
    stmts.push(stmt)
  }
  Ok({ pkg, targets, stmts })
}

///|
priv struct ComponentSource {
  pkg : String
  bytes : Bytes
  detail : ComponentDetail
  import_info_map : Map[String, ImportInfo]
  import_detail_map : Map[String, ComponentImportDetail]
  export_detail_map : Map[String, ComponentExportDetail]
}

///|
fn build_import_info_map(info : ComponentInfo) -> Map[String, ImportInfo] {
  let map : Map[String, ImportInfo] = {}
  for imp in info.imports {
    map.set(imp.name.to_string(), imp)
  }
  map
}

///|
fn build_import_detail_map2(
  detail : ComponentDetail,
) -> Map[String, ComponentImportDetail] {
  let map : Map[String, ComponentImportDetail] = {}
  for imp in detail.imports {
    map.set(imp.name.to_string(), imp)
  }
  map
}

///|
fn build_export_detail_map(
  detail : ComponentDetail,
) -> Map[String, ComponentExportDetail] {
  let map : Map[String, ComponentExportDetail] = {}
  for exp in detail.exports {
    map.set(exp.name.to_string(), exp)
  }
  map
}

///|
fn resolve_component_path(
  base_dir : String,
  pkg_name : String,
) -> String raise WacParseError {
  let parts : Array[String] = []
  for part in pkg_name.split(":") {
    parts.push(part.to_string())
  }
  if parts.length() != 2 {
    raise WacParseError::Message("invalid package name: " + pkg_name)
  }
  let ns = parts[0]
  let rest = parts[1]
  base_dir + "/deps/" + ns + "/" + rest + ".wasm"
}

///|
fn load_component_source(
  base_dir : String,
  pkg_name : String,
) -> Result[ComponentSource, String] {
  let path = resolve_component_path(base_dir, pkg_name) catch {
    e => return Err(e.to_string())
  }
  let bytes = @fs.read_file_to_bytes(path) catch {
    _ => return Err("failed to read component: " + path)
  }
  let info = match parse_component_info(bytes) {
    Ok(v) => v
    Err(e) => return Err("failed to parse component info: " + e.to_string())
  }
  let detail = match parse_component_detail(bytes) {
    Ok(v) => v
    Err(e) => return Err("failed to parse component detail: " + e.to_string())
  }
  Ok({
    pkg: pkg_name,
    bytes,
    detail,
    import_info_map: build_import_info_map(info),
    import_detail_map: build_import_detail_map2(detail),
    export_detail_map: build_export_detail_map(detail),
  })
}

///|
priv enum ArgSource {
  Import(ImportRef)
  Export(String, String)
  Instance(String)
}

///|
priv struct ImportBinding {
  local_name : String
  import_name : String
  target : String
  ty : WacImportType
}

///|
priv struct ImportRef {
  comp_name : String
  import_name : String
}

///|
priv struct InstanceBinding {
  index : Int
  pkg : String
}

///|
priv struct ArgPlan {
  name : Bytes
  kind : ExternKind
  source : ArgSource
}

///|
priv struct InstantiationPlan {
  name : String
  component : ComponentSource
  args : Array[ArgPlan]
}

///|
priv struct ExportItemPlan {
  inst : String
  name : String
  as_name : String?
}

///|
priv enum ExportPlan {
  All(String)
  Item(ExportItemPlan)
}

///|
fn collect_inst_dependencies(inst : InstantiationPlan) -> Array[String] {
  let deps : Array[String] = []
  for arg in inst.args {
    match arg.source {
      ArgSource::Export(inst_name, _) => deps.push(inst_name)
      ArgSource::Instance(inst_name) => deps.push(inst_name)
      _ => ()
    }
  }
  deps
}

///|
fn compute_reachable_instances(
  instantiations : Array[InstantiationPlan],
  exports : Array[ExportPlan],
) -> Map[String, Bool] {
  let deps_map : Map[String, Array[String]] = {}
  for inst in instantiations {
    deps_map.set(inst.name, collect_inst_dependencies(inst))
  }
  let queue : Array[String] = []
  let reachable : Map[String, Bool] = {}
  for exp in exports {
    match exp {
      ExportPlan::Item(plan) =>
        if not(reachable.contains(plan.inst)) {
          reachable.set(plan.inst, true)
          queue.push(plan.inst)
        }
      ExportPlan::All(inst_name) =>
        if not(reachable.contains(inst_name)) {
          reachable.set(inst_name, true)
          queue.push(inst_name)
        }
    }
  }
  let mut i = 0
  while i < queue.length() {
    let name = queue[i]
    i = i + 1
    match deps_map.get(name) {
      Some(deps) =>
        for dep in deps {
          if not(reachable.contains(dep)) {
            reachable.set(dep, true)
            queue.push(dep)
          }
        }
      None => ()
    }
  }
  reachable
}

///|
fn dce_wac_plans(
  instantiations : Array[InstantiationPlan],
  exports : Array[ExportPlan],
) -> (Array[InstantiationPlan], Array[ExportPlan]) {
  let reachable = compute_reachable_instances(instantiations, exports)
  let kept_insts : Array[InstantiationPlan] = []
  for inst in instantiations {
    if reachable.contains(inst.name) {
      kept_insts.push(inst)
    }
  }
  let kept_exports : Array[ExportPlan] = []
  for exp in exports {
    match exp {
      ExportPlan::Item(plan) =>
        if reachable.contains(plan.inst) {
          kept_exports.push(exp)
        }
      ExportPlan::All(inst_name) =>
        if reachable.contains(inst_name) {
          kept_exports.push(exp)
        }
    }
  }
  (kept_insts, kept_exports)
}

///|
priv enum ArgValue {
  Import(ImportBinding)
  Export(String, WacName)
  Instance(String)
}

///|

///|
fn resolve_arg_value(
  expr : WacExpr,
  import_bindings : Map[String, ImportBinding],
  instance_bindings : Map[String, InstanceBinding],
) -> Result[ArgValue, String] {
  match expr {
    WacExpr::Name(name) => {
      let key = name.to_string()
      match resolve_import_binding(import_bindings, key.to_string()) {
        Some(binding) => Ok(ArgValue::Import(binding))
        None =>
          if instance_bindings.contains(key) {
            Ok(ArgValue::Instance(name))
          } else {
            Err("unknown value `\{name}`")
          }
      }
    }
    WacExpr::Access(base, name) =>
      match base {
        WacExpr::Name(inst) => Ok(ArgValue::Export(inst, name))
        _ => Err("unsupported access base")
      }
    _ => Err("unsupported value")
  }
}

///|
fn import_name_matches(actual : String, alias_name : String) -> Bool {
  if actual == alias_name {
    return true
  }
  if actual.has_suffix("/" + alias_name) {
    return true
  }
  if actual.has_suffix(":" + alias_name) {
    return true
  }
  false
}

///|
fn last_segment(name : String) -> String {
  match name.rev_find("/") {
    Some(idx) =>
      normalize_segment(
        name[idx + 1:].to_string() catch {
          _ => name.to_string()
        },
      )
    None =>
      match name.rev_find(":") {
        Some(idx) =>
          normalize_segment(
            name[idx + 1:].to_string() catch {
              _ => name.to_string()
            },
          )
        None => normalize_segment(name.to_string())
      }
  }
}

///|
fn normalize_segment(segment : String) -> String {
  match segment.rev_find("@") {
    Some(idx) => segment[:idx].to_string() catch { _ => segment }
    None => segment
  }
}

///|
fn find_unique_suffix_match(names : Array[String], suffix : String) -> String? {
  let mut found : String? = None
  for name in names {
    if last_segment(name.to_string()) == suffix {
      match found {
        Some(_) => return None
        None => found = Some(name)
      }
    }
  }
  found
}

///|
fn import_names(comp : ComponentSource) -> Array[String] {
  let names : Array[String] = []
  for imp in comp.detail.imports {
    names.push(imp.name.to_string())
  }
  names
}

///|
fn export_names(comp : ComponentSource) -> Array[String] {
  let names : Array[String] = []
  for exp in comp.detail.exports {
    names.push(exp.name.to_string())
  }
  names
}

///|
fn infer_import_name(comp : ComponentSource, name : WacName) -> String {
  if name.exact {
    return name.value
  }
  let names = import_names(comp)
  match find_unique_suffix_match(names, name.value) {
    Some(v) => v
    None => name.value
  }
}

///|
fn infer_export_name(comp : ComponentSource, name : WacName) -> String {
  if name.exact {
    return name.value
  }
  let names = export_names(comp)
  match find_unique_suffix_match(names, name.value) {
    Some(v) => v
    None => name.value
  }
}

///|
fn infer_import_name_for_instance(
  comp : ComponentSource,
  pkg : String,
  local_name : String,
) -> String {
  if comp.import_detail_map.contains(pkg) {
    return pkg
  }
  let names = import_names(comp)
  match find_unique_suffix_match(names, local_name) {
    Some(v) => v
    None => local_name
  }
}

///|
fn resolve_import_binding(
  bindings : Map[String, ImportBinding],
  name : String,
) -> ImportBinding? {
  bindings.get(name)
}

///|
fn import_type_target(ty : WacImportType, import_name : String) -> String {
  match ty {
    WacImportType::Package(pkg) => pkg
    WacImportType::Ident(ident) => ident
    WacImportType::InlineInterface(_) => import_name
    WacImportType::InlineFunc(_) => import_name
  }
}

///|
fn import_type_default_name(
  ty : WacImportType,
  local_name : String,
) -> (String, WacImportType) {
  match ty {
    WacImportType::Package(pkg) => {
      let name = pkg.to_string()
      (name, WacImportType::Package(pkg))
    }
    WacImportType::Ident(ident) => {
      let name = ident.to_string()
      (name, WacImportType::Ident(ident))
    }
    WacImportType::InlineInterface(body) =>
      (local_name, WacImportType::InlineInterface(body))
    WacImportType::InlineFunc(body) =>
      (local_name, WacImportType::InlineFunc(body))
  }
}

///|
fn inline_wit_source(ty : WacImportType) -> (String, String) {
  let inline_name = "inline_import"
  let (source, name) = match ty {
    WacImportType::InlineInterface(body) => {
      let src = "package wac:inline;\n" +
        "world inline {\n" +
        "  import " +
        inline_name +
        ": interface " +
        body +
        "\n" +
        "}\n"
      (src, inline_name)
    }
    WacImportType::InlineFunc(sig) => {
      let src = "package wac:inline;\n" +
        "world inline {\n" +
        "  import " +
        inline_name +
        ": " +
        sig +
        ";\n" +
        "}\n"
      (src, inline_name)
    }
    _ => ("", inline_name)
  }
  (source, name)
}

///|
fn resolve_inline_wit(
  ty : WacImportType,
) -> Result[(@wit.Resolve, @wit.RWorld, String), String] {
  let (source, inline_name) = inline_wit_source(ty)
  let resolved = match @wit.resolve(source) {
    Ok(v) => v
    Err(e) => return Err("inline type parse error: " + e.to_string())
  }
  if resolved.worlds.length() == 0 {
    return Err("inline type parse error: missing world")
  }
  let world = resolved.worlds[0]
  Ok((resolved, world, inline_name))
}

///|
fn check_inline_import_type(
  detail : ComponentDetail,
  import_name : String,
  import_detail : ComponentImportDetail,
  ty : WacImportType,
  best_effort : Bool,
) -> Result[Unit, String] {
  match ty {
    WacImportType::InlineInterface(_) | WacImportType::InlineFunc(_) => ()
    _ => return Ok(())
  }
  let (inline_res, inline_world, inline_name) = match resolve_inline_wit(ty) {
    Ok(v) => v
    Err(e) => return if best_effort { Ok(()) } else { Err(e) }
  }
  let item = match inline_world.imports.get(inline_name) {
    Some(v) => v
    None =>
      return if best_effort {
        Ok(())
      } else {
        Err("inline import item missing")
      }
  }
  let global_space = build_global_space(detail.types)
  let instance_cache : Map[UInt, InstanceExportSet] = {}
  let ctx = { detail, global_space, instance_cache }
  let result = match item {
    @wit.RWorldItem::Interface(iface_ref) => {
      if import_detail.kind != ExternKind::Instance {
        return if best_effort {
          Ok(())
        } else {
          Err("inline import `\{import_name}` expects instance")
        }
      }
      let iface = inline_res.interfaces[iface_ref.id]
      let errors : Array[String] = []
      match
        resolve_instance_exports_from_type_ref(
          detail,
          import_detail.type_ref,
          global_space,
        ) {
        Ok(export_set) =>
          check_interface(
            iface,
            export_set,
            inline_res,
            ctx,
            "inline import `\{import_name}`",
            errors,
          )
        Err(e) => errors.push("inline import `\{import_name}`: " + e)
      }
      if errors.length() > 0 {
        Err(errors.join("\n"))
      } else {
        Ok(())
      }
    }
    @wit.RWorldItem::Function(func) => {
      if import_detail.kind != ExternKind::Func {
        return if best_effort {
          Ok(())
        } else {
          Err("inline import `\{import_name}` expects func")
        }
      }
      match
        resolve_func_type_in_space(ctx, global_space, import_detail.type_ref) {
        Some(resolved) =>
          match
            check_func_signature(import_name, func, resolved, inline_res, ctx) {
            Ok(_) => Ok(())
            Err(e) => Err("inline import `\{import_name}`: " + e)
          }
        None => Err("inline import `\{import_name}`: not a function type")
      }
    }
    @wit.RWorldItem::Type(_) => Ok(())
  }
  match result {
    Ok(_) => Ok(())
    Err(e) => if best_effort { Ok(()) } else { Err(e) }
  }
}

///|
fn match_import_binding(
  bindings : Map[String, ImportBinding],
  import_name : String,
) -> ImportBinding? {
  for _, binding in bindings {
    if import_name_matches(import_name, binding.target) ||
      import_name_matches(binding.target, import_name) {
      return Some(binding)
    }
  }
  for _, binding in bindings {
    if import_name_matches(import_name, binding.import_name) ||
      import_name_matches(binding.import_name, import_name) {
      return Some(binding)
    }
  }
  None
}

///|
fn find_import(
  comp : ComponentSource,
  alias_name : String,
  exact : Bool,
) -> Result[(String, ComponentImportDetail), String] {
  if exact {
    match comp.import_detail_map.get(alias_name) {
      Some(detail) => Ok((alias_name, detail))
      None => Err("unknown import `\{alias_name}` for `\{comp.pkg}`")
    }
  } else {
    match comp.import_detail_map.get(alias_name) {
      Some(detail) => Ok((alias_name, detail))
      None => {
        let alias_bytes = @utf8.encode(alias_name)
        for imp in comp.detail.imports {
          if imp.name == alias_bytes {
            return Ok((imp.name.to_string(), imp))
          }
          let name = imp.name.to_string()
          if import_name_matches(name, alias_name) {
            return Ok((name, imp))
          }
        }
        Err("unknown import `\{alias_name}` for `\{comp.pkg}`")
      }
    }
  }
}

///|
fn find_import_for_binding(
  comp : ComponentSource,
  binding : ImportBinding,
) -> Result[(String, ComponentImportDetail), String] {
  let mut found : (String, ComponentImportDetail)? = None
  for imp in comp.detail.imports {
    let name = imp.name.to_string()
    if import_name_matches(name, binding.target) ||
      import_name_matches(binding.target, name) {
      match found {
        Some(_) =>
          return Err(
            "ambiguous import for `\{binding.local_name}` in `\{comp.pkg}`",
          )
        None => found = Some((name, imp))
      }
    }
  }
  match found {
    Some(v) => Ok(v)
    None => {
      for imp in comp.detail.imports {
        let name = imp.name.to_string()
        if import_name_matches(name, binding.import_name) ||
          import_name_matches(binding.import_name, name) {
          return Ok((name, imp))
        }
      }
      Err("missing import `\{binding.target}` for `\{comp.pkg}`")
    }
  }
}

///|
fn find_export(
  comp : ComponentSource,
  alias_name : String,
  exact : Bool,
) -> Result[ComponentExportDetail, String] {
  if exact {
    match comp.export_detail_map.get(alias_name) {
      Some(detail) => Ok(detail)
      None => Err("unknown export `\{alias_name}` for `\{comp.pkg}`")
    }
  } else {
    match comp.export_detail_map.get(alias_name) {
      Some(detail) => Ok(detail)
      None => {
        let alias_bytes = @utf8.encode(alias_name)
        for exp in comp.detail.exports {
          if exp.name == alias_bytes {
            return Ok(exp)
          }
          let name = exp.name.to_string()
          if import_name_matches(name, alias_name) {
            return Ok(exp)
          }
        }
        Err("unknown export `\{alias_name}` for `\{comp.pkg}`")
      }
    }
  }
}

///|
fn get_component_from_cache(
  cache : Map[String, ComponentSource],
  base_dir : String,
  pkg_name : String,
) -> Result[ComponentSource, String] {
  match cache.get(pkg_name) {
    Some(c) => Ok(c)
    None => {
      let comp = match load_component_source(base_dir, pkg_name) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      cache.set(pkg_name, comp)
      Ok(comp)
    }
  }
}

///|
fn resolve_wac(
  doc : WacDocument,
  base_dir : String,
  best_effort : Bool,
) -> Result[(Array[InstantiationPlan], Array[ExportPlan]), String] {
  let component_cache : Map[String, ComponentSource] = {}
  let instantiations : Array[InstantiationPlan] = []
  let exports : Array[ExportPlan] = []
  let instance_bindings : Map[String, InstanceBinding] = {}
  let import_bindings : Map[String, ImportBinding] = {}
  for stmt in doc.stmts {
    match stmt {
      WacStmt::Import(import_stmt) => {
        if import_bindings.contains(import_stmt.local_name) ||
          instance_bindings.contains(import_stmt.local_name) {
          return Err("duplicate binding `\{import_stmt.local_name}`")
        }
        let target = import_type_target(
          import_stmt.ty,
          import_stmt.import_name.to_string(),
        )
        import_bindings.set(import_stmt.local_name, {
          local_name: import_stmt.local_name,
          import_name: import_stmt.import_name,
          target,
          ty: import_stmt.ty,
        })
      }
      WacStmt::Let(name, expr) =>
        match expr {
          WacExpr::New(new_expr) => {
            if import_bindings.contains(name) ||
              instance_bindings.contains(name) {
              return Err("duplicate binding `\{name}`")
            }
            let comp = match
              get_component_from_cache(component_cache, base_dir, new_expr.pkg) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let explicit_args : Map[String, ArgPlan] = {}
            let mut has_spread_all = false
            let spread_instances : Array[String] = []
            for arg in new_expr.args {
              match arg {
                WacArg::SpreadAll => has_spread_all = true
                WacArg::SpreadInstance(inst_name) =>
                  spread_instances.push(inst_name)
                WacArg::Named(arg_name, value_expr) => {
                  let arg_label = arg_name.value.to_string()
                  let import_lookup = infer_import_name(comp, arg_name)
                  let (import_name, import_detail) = match
                    find_import(comp, import_lookup, true) {
                    Ok(v) => v
                    Err(_) =>
                      match find_import(comp, arg_label.to_string(), false) {
                        Ok(v) => v
                        Err(e) => return Err(e)
                      }
                  }
                  let value = match
                    resolve_arg_value(
                      value_expr, import_bindings, instance_bindings,
                    ) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                  match value {
                    ArgValue::Import(binding) => {
                      if not(import_name_matches(import_name, binding.target)) &&
                        not(import_name_matches(binding.target, import_name)) &&
                        not(
                          import_name_matches(import_name, binding.import_name),
                        ) &&
                        not(
                          import_name_matches(binding.import_name, import_name),
                        ) {
                        return Err(
                          "import `\{binding.local_name}` does not match `\{import_name}`",
                        )
                      }
                      match
                        check_inline_import_type(
                          comp.detail,
                          import_name,
                          import_detail,
                          binding.ty,
                          best_effort,
                        ) {
                        Ok(_) => ()
                        Err(e) =>
                          return Err(
                            "import `\{binding.local_name}` inline type mismatch: " +
                            e,
                          )
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Import({
                          comp_name: import_name,
                          import_name: binding.import_name,
                        }),
                      }
                      explicit_args.set(import_name, plan)
                    }
                    ArgValue::Export(inst_name, export_name) => {
                      let inst_idx = match instance_bindings.get(inst_name) {
                        Some(v) => v.index
                        None => return Err("unknown instance `\{inst_name}`")
                      }
                      let inst_plan = instantiations[inst_idx]
                      let export_label = export_name.value.to_string()
                      let export_lookup = infer_export_name(
                        inst_plan.component,
                        export_name,
                      )
                      let export_detail = match
                        find_export(inst_plan.component, export_lookup, true) {
                        Ok(v) => v
                        Err(_) =>
                          match
                            find_export(
                              inst_plan.component,
                              export_label,
                              false,
                            ) {
                            Ok(v) => v
                            Err(e) => return Err(e)
                          }
                      }
                      match
                        check_plug_import_export_type(
                          comp.detail,
                          inst_plan.component.detail,
                          import_detail,
                          export_detail,
                          best_effort~,
                        ) {
                        Ok(_) => ()
                        Err(e) =>
                          return Err("import `\{arg_label}` mismatch: " + e)
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Export(
                          inst_name,
                          export_detail.name.to_string(),
                        ),
                      }
                      explicit_args.set(import_name, plan)
                    }
                    ArgValue::Instance(inst_name) => {
                      if import_detail.kind != ExternKind::Instance {
                        return Err("import `\{import_name}` expects instance")
                      }
                      if not(instance_bindings.contains(inst_name)) {
                        return Err("unknown instance `\{inst_name}`")
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Instance(inst_name),
                      }
                      explicit_args.set(import_name, plan)
                    }
                  }
                }
                WacArg::Inferred(value_expr) => {
                  let value = match
                    resolve_arg_value(
                      value_expr, import_bindings, instance_bindings,
                    ) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                  match value {
                    ArgValue::Import(binding) => {
                      let (import_name, import_detail) = match
                        find_import_for_binding(comp, binding) {
                        Ok(v) => v
                        Err(e) => return Err(e)
                      }
                      match
                        check_inline_import_type(
                          comp.detail,
                          import_name,
                          import_detail,
                          binding.ty,
                          best_effort,
                        ) {
                        Ok(_) => ()
                        Err(e) =>
                          return Err(
                            "import `\{binding.local_name}` inline type mismatch: " +
                            e,
                          )
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Import({
                          comp_name: import_name,
                          import_name: binding.import_name,
                        }),
                      }
                      explicit_args.set(import_name, plan)
                    }
                    ArgValue::Export(inst_name, export_name) => {
                      let export_label = export_name.value.to_string()
                      let import_lookup = infer_import_name(comp, export_name)
                      let (import_name, import_detail) = match
                        find_import(comp, import_lookup, true) {
                        Ok(v) => v
                        Err(_) =>
                          match find_import(comp, export_label, false) {
                            Ok(v) => v
                            Err(e) => return Err(e)
                          }
                      }
                      let inst_idx = match instance_bindings.get(inst_name) {
                        Some(v) => v.index
                        None => return Err("unknown instance `\{inst_name}`")
                      }
                      let inst_plan = instantiations[inst_idx]
                      let export_lookup = infer_export_name(
                        inst_plan.component,
                        export_name,
                      )
                      let export_detail = match
                        find_export(inst_plan.component, export_lookup, true) {
                        Ok(v) => v
                        Err(_) =>
                          match
                            find_export(
                              inst_plan.component,
                              export_label,
                              false,
                            ) {
                            Ok(v) => v
                            Err(e) => return Err(e)
                          }
                      }
                      match
                        check_plug_import_export_type(
                          comp.detail,
                          inst_plan.component.detail,
                          import_detail,
                          export_detail,
                          best_effort~,
                        ) {
                        Ok(_) => ()
                        Err(e) =>
                          return Err("import `\{import_name}` mismatch: " + e)
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Export(
                          inst_name,
                          export_detail.name.to_string(),
                        ),
                      }
                      explicit_args.set(import_name, plan)
                    }
                    ArgValue::Instance(inst_name) => {
                      let binding = match instance_bindings.get(inst_name) {
                        Some(v) => v
                        None => return Err("unknown instance `\{inst_name}`")
                      }
                      let local_name = inst_name.to_string()
                      let import_lookup = infer_import_name_for_instance(
                        comp,
                        binding.pkg.to_string(),
                        local_name,
                      )
                      let (import_name, import_detail) = match
                        find_import(comp, import_lookup, true) {
                        Ok(v) => v
                        Err(_) =>
                          match
                            find_import(comp, inst_name.to_string(), false) {
                            Ok(v) => v
                            Err(e) => return Err(e)
                          }
                      }
                      if import_detail.kind != ExternKind::Instance {
                        return Err("import `\{import_name}` expects instance")
                      }
                      let plan : ArgPlan = {
                        name: @utf8.encode(import_name),
                        kind: import_detail.kind,
                        source: ArgSource::Instance(inst_name),
                      }
                      explicit_args.set(import_name, plan)
                    }
                  }
                }
              }
            }
            for inst_name in spread_instances {
              let inst_idx = match instance_bindings.get(inst_name) {
                Some(v) => v.index
                None => return Err("unknown instance `\{inst_name}`")
              }
              let inst_plan = instantiations[inst_idx]
              let mut used = false
              for imp in comp.detail.imports {
                let imp_name = imp.name.to_string()
                if explicit_args.contains(imp_name) {
                  continue
                }
                let export_detail = match
                  find_export(inst_plan.component, imp_name, false) {
                  Ok(v) => v
                  Err(_) => continue
                }
                match
                  check_plug_import_export_type(
                    comp.detail,
                    inst_plan.component.detail,
                    imp,
                    export_detail,
                    best_effort~,
                  ) {
                  Ok(_) => ()
                  Err(_) => continue
                }
                let plan : ArgPlan = {
                  name: imp.name,
                  kind: imp.kind,
                  source: ArgSource::Export(
                    inst_name,
                    export_detail.name.to_string(),
                  ),
                }
                explicit_args.set(imp_name, plan)
                used = true
              }
              if not(used) {
                return Err(
                  "spread instance `\{inst_name}` has no matching exports",
                )
              }
            }
            let args : Array[ArgPlan] = []
            for imp in comp.detail.imports {
              let imp_name = imp.name.to_string()
              match explicit_args.get(imp_name) {
                Some(p) => args.push(p)
                None =>
                  if has_spread_all {
                    let binding = match_import_binding(
                      import_bindings, imp_name,
                    )
                    let import_name = match binding {
                      Some(b) => b.import_name
                      None => imp_name
                    }
                    match binding {
                      Some(b) =>
                        match
                          check_inline_import_type(
                            comp.detail,
                            imp_name,
                            imp,
                            b.ty,
                            best_effort,
                          ) {
                          Ok(_) => ()
                          Err(e) =>
                            return Err(
                              "import `\{b.local_name}` inline type mismatch: " +
                              e,
                            )
                        }
                      None => ()
                    }
                    args.push({
                      name: imp.name,
                      kind: imp.kind,
                      source: ArgSource::Import({
                        comp_name: imp_name,
                        import_name,
                      }),
                    })
                  } else {
                    return Err(
                      "missing import `\{imp_name}` for `\{new_expr.pkg}`",
                    )
                  }
              }
            }
            let plan : InstantiationPlan = { name, component: comp, args }
            instance_bindings.set(name, {
              index: instantiations.length(),
              pkg: new_expr.pkg,
            })
            instantiations.push(plan)
          }
          _ => return Err("let must bind a new expression")
        }
      WacStmt::Export(export_stmt) =>
        match export_stmt.expr {
          WacExpr::Name(name) =>
            if export_stmt.all {
              exports.push(ExportPlan::All(name))
            } else {
              return Err("export expects access or ...")
            }
          WacExpr::Access(base, name) =>
            match base {
              WacExpr::Name(inst) =>
                if export_stmt.all {
                  return Err("export ... expects instance name")
                } else {
                  let inst_idx = match instance_bindings.get(inst) {
                    Some(v) => v.index
                    None => return Err("unknown instance `\{inst}`")
                  }
                  let inst_plan = instantiations[inst_idx]
                  let export_lookup = infer_export_name(
                    inst_plan.component,
                    name,
                  )
                  let export_detail = match
                    find_export(inst_plan.component, export_lookup, true) {
                    Ok(v) => v
                    Err(_) =>
                      match
                        find_export(
                          inst_plan.component,
                          name.value.to_string(),
                          false,
                        ) {
                        Ok(v) => v
                        Err(e) => return Err(e)
                      }
                  }
                  exports.push(
                    ExportPlan::Item({
                      inst,
                      name: export_detail.name.to_string(),
                      as_name: export_stmt.as_name,
                    }),
                  )
                }
              _ => return Err("unsupported export expression")
            }
          _ => return Err("unsupported export expression")
        }
    }
  }
  Ok((instantiations, exports))
}

///|
fn merge_import_spec(
  merged : Array[ImportInfo],
  merged_details : Array[ComponentImportDetail],
  merged_sources : Array[ComponentDetail],
  index_map : Map[String, UInt],
  info : ImportInfo,
  detail : ComponentImportDetail,
  source_detail : ComponentDetail,
  best_effort : Bool,
) -> Result[UInt, String] {
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
        Err(msg) => Err("import type conflict for `\{key}`: " + msg)
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
fn build_alias_key(inst : String, name : String) -> String {
  inst + "#" + name
}

///|
fn require_instance_idx(
  map : Map[String, Int],
  name : String,
) -> Result[Int, String] {
  match map.get(name) {
    Some(v) => Ok(v)
    None => Err("unknown instance `\{name}`")
  }
}

///|
fn dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => {
      let prefix = path[:idx] catch { _ => "." }
      if prefix.is_empty() {
        "."
      } else {
        prefix.to_string()
      }
    }
    None => "."
  }
}

///|
pub fn compose_wac_source(
  source : String,
  base_dir : String,
  best_effort? : Bool = false,
  dce? : Bool = false,
) -> Result[Bytes, String] {
  let doc = match parse_wac(source) {
    Ok(v) => v
    Err(e) => return Err(e.to_string())
  }
  let (instantiations, exports) = match
    resolve_wac(doc, base_dir, best_effort) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let (instantiations, exports) = if dce {
    dce_wac_plans(instantiations, exports)
  } else {
    (instantiations, exports)
  }
  let instance_index_map : Map[String, Int] = {}
  for i in 0..<instantiations.length() {
    instance_index_map.set(instantiations[i].name, i)
  }
  let component_sources : Map[String, ComponentSource] = {}
  let component_order : Array[String] = []
  for inst in instantiations {
    let pkg = inst.component.pkg
    if not(component_sources.contains(pkg)) {
      component_sources.set(pkg, inst.component)
      component_order.push(pkg)
    }
  }
  let component_index_map : Map[String, UInt] = {}
  for i in 0..<component_order.length() {
    component_index_map.set(component_order[i], i.reinterpret_as_uint())
  }
  let merged_imports : Array[ImportInfo] = []
  let merged_details : Array[ComponentImportDetail] = []
  let merged_sources : Array[ComponentDetail] = []
  let import_index_map : Map[String, UInt] = {}
  for inst in instantiations {
    let comp = inst.component
    for arg in inst.args {
      match arg.source {
        ArgSource::Import(import_ref) => {
          let info = match comp.import_info_map.get(import_ref.comp_name) {
            Some(v) => v
            None =>
              return Err("missing import info for `\{import_ref.comp_name}`")
          }
          let detail = match comp.import_detail_map.get(import_ref.comp_name) {
            Some(v) => v
            None =>
              return Err("missing import detail for `\{import_ref.comp_name}`")
          }
          let info2 = if import_ref.import_name != import_ref.comp_name {
            {
              name: @utf8.encode(import_ref.import_name),
              kind: info.kind,
              raw_desc: info.raw_desc,
            }
          } else {
            info
          }
          let detail2 = if import_ref.import_name != import_ref.comp_name {
            {
              name: @utf8.encode(import_ref.import_name),
              kind: detail.kind,
              type_ref: detail.type_ref,
            }
          } else {
            detail
          }
          match
            merge_import_spec(
              merged_imports,
              merged_details,
              merged_sources,
              import_index_map,
              info2,
              detail2,
              comp.detail,
              best_effort,
            ) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
        }
        ArgSource::Export(_, _) => ()
        ArgSource::Instance(_) => ()
      }
    }
  }
  let index_state = IndexState::new()
  let component_indices : Array[UInt] = Array::make(
    component_order.length(),
    0U,
  )
  for i in 0..<component_order.length() {
    component_indices[i] = index_state.next(ExternKind::Component)
  }
  let merged_import_indices : Array[UInt] = Array::make(
    merged_imports.length(),
    0U,
  )
  for i in 0..<merged_imports.length() {
    let imp = merged_imports[i]
    merged_import_indices[i] = index_state.next(imp.kind)
  }
  let instance_indices : Array[UInt] = Array::make(instantiations.length(), 0U)
  for i in 0..<instantiations.length() {
    instance_indices[i] = index_state.next(ExternKind::Instance)
  }
  let alias_map : Map[String, UInt] = {}
  let alias_entries : Array[(UInt, Bytes, ExternKind)] = []
  for inst in instantiations {
    for arg in inst.args {
      match arg.source {
        ArgSource::Export(inst_name, export_name) => {
          let key = build_alias_key(inst_name, export_name)
          if not(alias_map.contains(key)) {
            let inst_pos = match
              require_instance_idx(instance_index_map, inst_name) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let inst_idx = instance_indices[inst_pos]
            let inst_plan = instantiations[inst_pos]
            let export_detail = match
              find_export(inst_plan.component, export_name, true) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let alias_idx = index_state.next(export_detail.kind)
            alias_map.set(key, alias_idx)
            alias_entries.push(
              (inst_idx, export_detail.name, export_detail.kind),
            )
          }
        }
        _ => ()
      }
    }
  }
  for exp in exports {
    match exp {
      ExportPlan::Item(plan) => {
        let inst_name = plan.inst
        let export_name = plan.name
        let key = build_alias_key(inst_name, export_name)
        if not(alias_map.contains(key)) {
          let inst_pos = match
            require_instance_idx(instance_index_map, inst_name) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let inst_idx = instance_indices[inst_pos]
          let inst_plan = instantiations[inst_pos]
          let export_detail = match
            find_export(inst_plan.component, export_name, true) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          let alias_idx = index_state.next(export_detail.kind)
          alias_map.set(key, alias_idx)
          alias_entries.push((inst_idx, export_detail.name, export_detail.kind))
        }
      }
      ExportPlan::All(inst_name) => {
        let inst_pos = match
          require_instance_idx(instance_index_map, inst_name) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let inst_idx = instance_indices[inst_pos]
        let inst_plan = instantiations[inst_pos]
        for name, export_detail in inst_plan.component.export_detail_map {
          let key = build_alias_key(inst_name, name)
          if not(alias_map.contains(key)) {
            let alias_idx = index_state.next(export_detail.kind)
            alias_map.set(key, alias_idx)
            alias_entries.push(
              (inst_idx, export_detail.name, export_detail.kind),
            )
          }
        }
      }
    }
  }
  let out : Array[Byte] = []
  append_bytes(out, [
    0x00U.to_byte(),
    0x61U.to_byte(),
    0x73U.to_byte(),
    0x6dU.to_byte(),
  ])
  append_bytes(out, [0x0dU.to_byte(), 0x00U.to_byte()])
  append_bytes(out, [0x01U.to_byte(), 0x00U.to_byte()])

  // Section 4: component definitions
  for pkg in component_order {
    let comp = component_sources[pkg]
    push_section(out, 4U, comp.bytes.to_array())
  }

  // Section 10: imports
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

  // Section 5: instances
  if instantiations.length() > 0 {
    let payload : Array[Byte] = []
    append_bytes(
      payload,
      encode_u32_leb128(instantiations.length().reinterpret_as_uint()),
    )
    for i in 0..<instantiations.length() {
      let inst = instantiations[i]
      let comp_order_idx = component_index_map[inst.component.pkg].reinterpret_as_int()
      let comp_idx = component_indices[comp_order_idx]
      let args : Array[InstantiateArgEntry] = []
      for arg in inst.args {
        match arg.source {
          ArgSource::Import(import_ref) => {
            let merged_idx = import_index_map[import_ref.import_name]
            let idx = merged_import_indices[merged_idx.reinterpret_as_int()]
            args.push({ name: arg.name, kind: arg.kind, idx })
          }
          ArgSource::Export(inst_name, export_name) => {
            let key = build_alias_key(inst_name, export_name)
            let idx = alias_map[key]
            args.push({ name: arg.name, kind: arg.kind, idx })
          }
          ArgSource::Instance(inst_name) => {
            let inst_pos = match
              require_instance_idx(instance_index_map, inst_name) {
              Ok(v) => v
              Err(e) => return Err(e)
            }
            let idx = instance_indices[inst_pos]
            args.push({ name: arg.name, kind: arg.kind, idx })
          }
        }
      }
      let inst_bytes = encode_instance(comp_idx, args)
      append_bytes(payload, inst_bytes)
    }
    push_section(out, 5U, payload)
  }

  // Section 6: aliases
  if alias_entries.length() > 0 {
    let payload : Array[Byte] = []
    append_bytes(
      payload,
      encode_u32_leb128(alias_entries.length().reinterpret_as_uint()),
    )
    for entry in alias_entries {
      let (inst_idx, name, kind) = entry
      append_bytes(payload, encode_alias(kind, inst_idx, name))
    }
    push_section(out, 6U, payload)
  }

  // Section 11: exports
  let export_payload : Array[Byte] = []
  let mut export_count = 0
  for exp in exports {
    match exp {
      ExportPlan::Item(plan) => {
        let inst_name = plan.inst
        let export_name = plan.name
        let inst_pos = match
          require_instance_idx(instance_index_map, inst_name) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let inst_plan = instantiations[inst_pos]
        let export_detail = match
          find_export(inst_plan.component, export_name, true) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let key = build_alias_key(inst_name, export_name)
        let idx = alias_map[key]
        let export_name_bytes = match plan.as_name {
          Some(as_name) => @utf8.encode(as_name)
          None => export_detail.name
        }
        append_bytes(
          export_payload,
          encode_export(export_name_bytes, export_detail.kind, idx),
        )
        export_count = export_count + 1
      }
      ExportPlan::All(inst_name) => {
        let inst_pos = match
          require_instance_idx(instance_index_map, inst_name) {
          Ok(v) => v
          Err(e) => return Err(e)
        }
        let inst_plan = instantiations[inst_pos]
        for name, export_detail in inst_plan.component.export_detail_map {
          let key = build_alias_key(inst_name, name)
          let idx = alias_map[key]
          append_bytes(
            export_payload,
            encode_export(export_detail.name, export_detail.kind, idx),
          )
          export_count = export_count + 1
        }
      }
    }
  }
  if export_count > 0 {
    let payload : Array[Byte] = []
    append_bytes(payload, encode_u32_leb128(export_count.reinterpret_as_uint()))
    append_bytes(payload, export_payload)
    push_section(out, 11U, payload)
  }
  let result = Bytes::from_array(out)
  match doc.targets {
    Some(target) => {
      let wit_dir = base_dir + "/wit"
      match @wit.resolve_path(wit_dir, world=target) {
        Ok(resolved) =>
          match check_component_targets(result, resolved) {
            Ok(_) => ()
            Err(e) =>
              if not(best_effort) {
                return Err("targets check failed: " + e)
              }
          }
        Err(e) =>
          if not(best_effort) {
            return Err("targets resolve failed: " + e.to_string())
          }
      }
    }
    None => ()
  }
  Ok(result)
}

///|
pub fn resolve_wac_summary(
  source : String,
  base_dir : String,
  best_effort? : Bool = false,
) -> Result[WacResolveSummary, String] {
  let doc = match parse_wac(source) {
    Ok(v) => v
    Err(e) => return Err(e.to_string())
  }
  let (instantiations, exports) = match
    resolve_wac(doc, base_dir, best_effort) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let components : Array[String] = []
  let component_seen : Map[String, Bool] = {}
  for inst in instantiations {
    let pkg = inst.component.pkg
    if not(component_seen.contains(pkg)) {
      component_seen.set(pkg, true)
      components.push(pkg)
    }
  }
  let import_names : Array[String] = []
  let import_seen : Map[String, Bool] = {}
  for inst in instantiations {
    for arg in inst.args {
      match arg.source {
        ArgSource::Import(import_ref) =>
          if not(import_seen.contains(import_ref.import_name)) {
            import_seen.set(import_ref.import_name, true)
            import_names.push(import_ref.import_name)
          }
        ArgSource::Instance(_) => ()
        _ => ()
      }
    }
  }
  let inst_summaries : Array[WacInstantiationSummary] = []
  for inst in instantiations {
    let args : Array[String] = []
    for arg in inst.args {
      match arg.source {
        ArgSource::Import(import_ref) =>
          args.push("import:" + import_ref.import_name)
        ArgSource::Export(inst_name, export_name) =>
          args.push("export:" + inst_name + "." + export_name)
        ArgSource::Instance(inst_name) => args.push("instance:" + inst_name)
      }
    }
    inst_summaries.push({ name: inst.name, component: inst.component.pkg, args })
  }
  let export_list : Array[String] = []
  for exp in exports {
    match exp {
      ExportPlan::Item(plan) => {
        let base = plan.inst + "." + plan.name
        let entry = match plan.as_name {
          Some(as_name) => base + " as " + as_name
          None => base
        }
        export_list.push(entry)
      }
      ExportPlan::All(inst_name) => export_list.push(inst_name + ".*")
    }
  }
  Ok({
    pkg: doc.pkg,
    components,
    instantiations: inst_summaries,
    exports: export_list,
    imports: import_names,
  })
}

///|
pub fn compose_wac_file(
  path : String,
  best_effort? : Bool = false,
  dce? : Bool = false,
) -> Result[Bytes, String] {
  let source = @fs.read_file_to_string(path) catch {
    _ => return Err("failed to read: " + path)
  }
  let base_dir = dirname(path)
  compose_wac_source(source, base_dir, best_effort~, dce~)
}
