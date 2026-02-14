/// Type-related code generation

///|
/// Get the size of a type in bytes (for canonical ABI)
fn Generator::type_size(self : Generator, ty : @resolve.Type) -> Int {
  match ty {
    Bool | U8 | S8 => 1
    U16 | S16 => 2
    U32 | S32 | F32 | Char => 4
    U64 | S64 | F64 => 8
    String_ => 8 // ptr + len
    Id(id) => {
      let typedef = self.resolve.types[id]
      match typedef.kind {
        Record(fields) => {
          let mut size = 0
          for field in fields {
            // Align each field
            let field_align = self.type_align(field.field_type)
            size = (size + field_align - 1) & -field_align
            size = size + self.type_size(field.field_type)
          }
          size
        }
        Tuple(types) => {
          let mut size = 0
          for t in types {
            let align = self.type_align(t)
            size = (size + align - 1) & -align
            size = size + self.type_size(t)
          }
          size
        }
        Variant(cases) => {
          // discriminant (4 bytes) + max payload size
          let mut max_payload = 0
          for case in cases {
            match case.case_type {
              Some(t) => {
                let payload_size = self.type_size(t)
                if payload_size > max_payload {
                  max_payload = payload_size
                }
              }
              None => ()
            }
          }
          4 + max_payload
        }
        List(_) | Option(_) | Result(ok=_, err=_) => 8
        Flags(flags) =>
          // Flags are stored as u32 bitmask (up to 32 flags)
          if flags.length() <= 8 {
            1
          } else if flags.length() <= 16 {
            2
          } else {
            4
          }
        Enum(_) => 4 // discriminant only
        _ => 4
      }
    }
  }
}

///|
/// Get the alignment of a type (for canonical ABI)
fn Generator::type_align(self : Generator, ty : @resolve.Type) -> Int {
  match ty {
    Bool | U8 | S8 => 1
    U16 | S16 => 2
    U32 | S32 | F32 | Char => 4
    U64 | S64 | F64 => 8
    String_ => 4 // pointer alignment
    Id(id) => {
      let typedef = self.resolve.types[id]
      match typedef.kind {
        Record(fields) => {
          let mut max_align = 1
          for field in fields {
            let align = self.type_align(field.field_type)
            if align > max_align {
              max_align = align
            }
          }
          max_align
        }
        Tuple(types) => {
          let mut max_align = 1
          for t in types {
            let align = self.type_align(t)
            if align > max_align {
              max_align = align
            }
          }
          max_align
        }
        Variant(cases) => {
          let mut max_align = 4 // discriminant
          for case in cases {
            match case.case_type {
              Some(t) => {
                let align = self.type_align(t)
                if align > max_align {
                  max_align = align
                }
              }
              None => ()
            }
          }
          max_align
        }
        List(_) | Option(_) | Result(ok=_, err=_) => 4
        Flags(flags) =>
          if flags.length() <= 8 {
            1
          } else if flags.length() <= 16 {
            2
          } else {
            4
          }
        _ => 4
      }
    }
  }
}

///|
/// Generate code to lift a list element
fn Generator::generate_list_elem_lift(
  self : Generator,
  elem_ty : @resolve.Type,
  ptr_var : String,
) -> String {
  match elem_ty {
    Bool => "@cabi.cabi_read_u8(" + ptr_var + ") != b'\\x00'"
    U8 => "@cabi.cabi_read_u8(" + ptr_var + ")"
    S8 => "@cabi.cabi_read_u8(" + ptr_var + ").to_int()"
    U16 =>
      "(@cabi.cabi_read_i32(" + ptr_var + ") & 0xffff).reinterpret_as_uint()"
    S16 => "@cabi.cabi_read_i32(" + ptr_var + ") & 0xffff"
    U32 => "@cabi.cabi_read_i32(" + ptr_var + ").reinterpret_as_uint()"
    S32 => "@cabi.cabi_read_i32(" + ptr_var + ")"
    U64 => "@cabi.cabi_read_i64(" + ptr_var + ").reinterpret_as_uint64()"
    S64 => "@cabi.cabi_read_i64(" + ptr_var + ")"
    F32 => "@cabi.cabi_read_f32(" + ptr_var + ")"
    F64 => "@cabi.cabi_read_f64(" + ptr_var + ")"
    Char => "@cabi.cabi_read_i32(" + ptr_var + ").unsafe_to_char()"
    String_ =>
      "@cabi.cabi_lift_string(@cabi.cabi_read_i32(" +
      ptr_var +
      "), @cabi.cabi_read_i32(" +
      ptr_var +
      " + 4))"
    Id(id) => {
      let typedef = self.resolve.types[id]
      match typedef.kind {
        Record(fields) => {
          let type_name = self.resolve_type_name(id)
          let sb = StringBuilder::new()
          sb.write_string("({ ")
          for i, field in fields {
            if i > 0 {
              sb.write_string(", ")
            }
            let field_name = to_snake_case(field.name)
            let mut field_offset = 0
            for j = 0; j < i; j = j + 1 {
              let prev_align = self.type_align(fields[j].field_type)
              field_offset = (field_offset + prev_align - 1) & -prev_align
              field_offset = field_offset + self.type_size(fields[j].field_type)
            }
            sb.write_string(field_name)
            sb.write_string(": ")
            sb.write_string(
              self.generate_list_elem_lift(
                field.field_type,
                ptr_var + " + " + field_offset.to_string(),
              ),
            )
          }
          sb.write_string(" } : ")
          sb.write_string(type_name)
          sb.write_string(")")
          sb.to_string()
        }
        Tuple(types) => {
          let sb = StringBuilder::new()
          sb.write_string("(")
          for i, t in types {
            if i > 0 {
              sb.write_string(", ")
            }
            let mut elem_offset = 0
            for j = 0; j < i; j = j + 1 {
              let prev_align = self.type_align(types[j])
              elem_offset = (elem_offset + prev_align - 1) & -prev_align
              elem_offset = elem_offset + self.type_size(types[j])
            }
            sb.write_string(
              self.generate_list_elem_lift(
                t,
                ptr_var + " + " + elem_offset.to_string(),
              ),
            )
          }
          sb.write_string(")")
          sb.to_string()
        }
        Variant(cases) => {
          let type_name = self.resolve_type_name(id)
          let sb = StringBuilder::new()
          sb.write_string("(match @cabi.cabi_read_i32(")
          sb.write_string(ptr_var)
          sb.write_string(") {\n")
          for i, case in cases {
            sb.write_string("        ")
            sb.write_string(i.to_string())
            sb.write_string(" => ")
            sb.write_string(to_pascal_case(case.name))
            match case.case_type {
              Some(payload_ty) => {
                sb.write_string("(")
                sb.write_string(
                  self.generate_list_elem_lift(
                    payload_ty,
                    ptr_var + " + 4",
                  ),
                )
                sb.write_string(")")
              }
              None => ()
            }
            sb.write_string("\n")
          }
          sb.write_string("        _ => abort(\"invalid variant discriminant\")\n")
          sb.write_string("      } : ")
          sb.write_string(type_name)
          sb.write_string(")")
          sb.to_string()
        }
        Enum(_) => {
          let type_name = self.resolve_type_name(id)
          type_name + "::from_ordinal(@cabi.cabi_read_i32(" + ptr_var + "))"
        }
        List(inner) => {
          let elem_size = self.type_size(inner)
          let list_type = self.type_name(Id(id))
          let sb = StringBuilder::new()
          sb.write_string("({ let list_ptr = @cabi.cabi_read_i32(")
          sb.write_string(ptr_var)
          sb.write_string("); let list_len = @cabi.cabi_read_i32(")
          sb.write_string(ptr_var)
          sb.write_string(" + 4); let arr : ")
          sb.write_string(list_type)
          sb.write_string(" = Array::new(capacity=list_len); for i = 0; i < list_len; i = i + 1 { arr.push(")
          sb.write_string(
            self.generate_list_elem_lift(
              inner,
              "list_ptr + i * " + elem_size.to_string(),
            ),
          )
          sb.write_string(") }; arr })")
          sb.to_string()
        }
        Option(inner) => {
          let sb = StringBuilder::new()
          sb.write_string("(if @cabi.cabi_read_i32(")
          sb.write_string(ptr_var)
          sb.write_string(") != 0 { Some(")
          sb.write_string(
            self.generate_list_elem_lift(inner, ptr_var + " + 4"),
          )
          sb.write_string(") } else { None })")
          sb.to_string()
        }
        _ =>
          "@cabi.cabi_read_i32(" + ptr_var + ") // TODO: lift complex element"
      }
    }
  }
}

///|
/// Generate code to lower a value to memory at given pointer expression
fn Generator::generate_value_lower(
  self : Generator,
  sb : StringBuilder,
  ptr_expr : String,
  ty : @resolve.Type,
  val_expr : String,
  indent : String,
) -> Unit {
  match ty {
    Bool => {
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_u8(")
      sb.write_string(ptr_expr)
      sb.write_string(", if ")
      sb.write_string(val_expr)
      sb.write_string(" { b'\\x01' } else { b'\\x00' })\n")
    }
    U8 | S8 => {
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_u8(")
      sb.write_string(ptr_expr)
      sb.write_string(", ")
      sb.write_string(val_expr)
      sb.write_string(")\n")
    }
    U16 | U32 => {
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_i32(")
      sb.write_string(ptr_expr)
      sb.write_string(", ")
      sb.write_string(val_expr)
      sb.write_string(".reinterpret_as_int())\n")
    }
    S16 | S32 => {
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_i32(")
      sb.write_string(ptr_expr)
      sb.write_string(", ")
      sb.write_string(val_expr)
      sb.write_string(")\n")
    }
    U64 => {
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_i64(")
      sb.write_string(ptr_expr)
      sb.write_string(", ")
      sb.write_string(val_expr)
      sb.write_string(".reinterpret_as_int64())\n")
    }
    S64 => {
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_i64(")
      sb.write_string(ptr_expr)
      sb.write_string(", ")
      sb.write_string(val_expr)
      sb.write_string(")\n")
    }
    F32 => {
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_f32(")
      sb.write_string(ptr_expr)
      sb.write_string(", ")
      sb.write_string(val_expr)
      sb.write_string(")\n")
    }
    F64 => {
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_f64(")
      sb.write_string(ptr_expr)
      sb.write_string(", ")
      sb.write_string(val_expr)
      sb.write_string(")\n")
    }
    Char => {
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_i32(")
      sb.write_string(ptr_expr)
      sb.write_string(", ")
      sb.write_string(val_expr)
      sb.write_string(".to_int())\n")
    }
    String_ => {
      sb.write_string(indent)
      sb.write_string("let (str_ptr, str_len) = @cabi.cabi_lower_string(")
      sb.write_string(val_expr)
      sb.write_string(")\n")
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_i32(")
      sb.write_string(ptr_expr)
      sb.write_string(", str_ptr)\n")
      sb.write_string(indent)
      sb.write_string("@cabi.cabi_write_i32(")
      sb.write_string(ptr_expr)
      sb.write_string(" + 4, str_len)\n")
    }
    Id(id) => {
      let typedef = self.resolve.types[id]
      match typedef.kind {
        Record(fields) => {
          // Lower record fields recursively
          let mut offset = 0
          for field in fields {
            let field_name = to_snake_case(field.name)
            let field_align = self.type_align(field.field_type)
            offset = (offset + field_align - 1) & -field_align
            let field_ptr = if offset == 0 {
              ptr_expr
            } else {
              ptr_expr + " + " + offset.to_string()
            }
            self.generate_value_lower(
              sb,
              field_ptr,
              field.field_type,
              val_expr + "." + field_name,
              indent,
            )
            offset = offset + self.type_size(field.field_type)
          }
        }
        List(inner) => {
          let elem_size = self.type_size(inner)
          let elem_align = self.type_align(inner)
          sb.write_string(indent)
          sb.write_string("let len = ")
          sb.write_string(val_expr)
          sb.write_string(".length()\n")
          sb.write_string(indent)
          sb.write_string("let elem_size = ")
          sb.write_string(elem_size.to_string())
          sb.write_string("\n")
          sb.write_string(indent)
          sb.write_string("let ptr = @cabi.cabi_realloc(0, 0, ")
          sb.write_string(elem_align.to_string())
          sb.write_string(", len * elem_size)\n")
          sb.write_string(indent)
          sb.write_string("for i, elem in ")
          sb.write_string(val_expr)
          sb.write_string(" {\n")
          sb.write_string(indent)
          sb.write_string("  let elem_ptr = ptr + i * elem_size\n")
          self.generate_list_elem_lower(sb, inner, "elem_ptr", "elem")
          sb.write_string(indent)
          sb.write_string("}\n")
          sb.write_string(indent)
          sb.write_string("@cabi.cabi_write_i32(")
          sb.write_string(ptr_expr)
          sb.write_string(", ptr)\n")
          sb.write_string(indent)
          sb.write_string("@cabi.cabi_write_i32(")
          sb.write_string(ptr_expr)
          sb.write_string(" + 4, len)\n")
        }
        Variant(cases) => {
          // Lower variant: write discriminant + payload
          sb.write_string(indent)
          sb.write_string("match ")
          sb.write_string(val_expr)
          sb.write_string(" {\n")
          for i, case in cases {
            let case_name = to_pascal_case(case.name)
            sb.write_string(indent)
            sb.write_string("  ")
            sb.write_string(case_name)
            match case.case_type {
              Some(payload_ty) => {
                sb.write_string("(payload) => {\n")
                sb.write_string(indent)
                sb.write_string("    @cabi.cabi_write_i32(")
                sb.write_string(ptr_expr)
                sb.write_string(", ")
                sb.write_string(i.to_string())
                sb.write_string(")\n")
                self.generate_value_lower(
                  sb,
                  ptr_expr + " + 4",
                  payload_ty,
                  "payload",
                  indent + "    ",
                )
                sb.write_string(indent)
                sb.write_string("  }\n")
              }
              None => {
                sb.write_string(" => @cabi.cabi_write_i32(")
                sb.write_string(ptr_expr)
                sb.write_string(", ")
                sb.write_string(i.to_string())
                sb.write_string(")\n")
              }
            }
          }
          sb.write_string(indent)
          sb.write_string("}\n")
        }
        Enum(_) => {
          // Lower enum: write ordinal
          sb.write_string(indent)
          sb.write_string("@cabi.cabi_write_i32(")
          sb.write_string(ptr_expr)
          sb.write_string(", ")
          sb.write_string(val_expr)
          sb.write_string(".ordinal())\n")
        }
        Option(inner) => {
          // Lower option: discriminant + payload
          sb.write_string(indent)
          sb.write_string("match ")
          sb.write_string(val_expr)
          sb.write_string(" {\n")
          sb.write_string(indent)
          sb.write_string("  Some(payload) => {\n")
          sb.write_string(indent)
          sb.write_string("    @cabi.cabi_write_i32(")
          sb.write_string(ptr_expr)
          sb.write_string(", 1)\n")
          self.generate_value_lower(
            sb,
            ptr_expr + " + 4",
            inner,
            "payload",
            indent + "    ",
          )
          sb.write_string(indent)
          sb.write_string("  }\n")
          sb.write_string(indent)
          sb.write_string("  None => @cabi.cabi_write_i32(")
          sb.write_string(ptr_expr)
          sb.write_string(", 0)\n")
          sb.write_string(indent)
          sb.write_string("}\n")
        }
        _ => {
          sb.write_string(indent)
          sb.write_string("// TODO: lower nested type ")
          sb.write_string(val_expr)
          sb.write_string("\n")
        }
      }
    }
  }
}

///|
/// Generate code to lower a list element (convenience wrapper)
fn Generator::generate_list_elem_lower(
  self : Generator,
  sb : StringBuilder,
  elem_ty : @resolve.Type,
  ptr_var : String,
  elem_var : String,
) -> Unit {
  self.generate_value_lower(sb, ptr_var, elem_ty, elem_var, "    ")
}

///|
fn Generator::ffi_to_type_conv(
  self : Generator,
  result : @resolve.Type?,
) -> (String, String) {
  // Returns (prefix, suffix) for converting result back to FFI type
  match result {
    None => ("", "")
    Some(ty) =>
      match ty {
        U8 => ("", ".to_int()")
        U16 | U32 => ("", ".reinterpret_as_int()")
        U64 => ("", ".reinterpret_as_int64()")
        Char => ("", ".to_int()")
        Id(id) => {
          let typedef = self.resolve.types[id]
          match typedef.kind {
            Flags(_) => ("", ".to_bits()")
            Enum(_) => ("", ".ordinal()") // Enum returns discriminant
            Resource => ("", ".0") // Resource handle: extract Int from newtype
            Handle(_) => ("", ".0") // Handle (own/borrow): extract Int from newtype
            _ => ("", "")
          }
        }
        _ => ("", "")
      }
  }
}

///|
fn Generator::param_list(
  self : Generator,
  params : Array[(String, @resolve.Type)],
) -> String {
  let parts : Array[String] = []
  for param in params {
    let (name, ty) = param
    let snake_name = to_snake_case(name)
    let safe_name = if snake_name == "self" { "handle" } else { snake_name }
    parts.push(safe_name + " : " + self.type_name(ty))
  }
  parts.join(", ")
}

///|
fn Generator::result_type(self : Generator, result : @resolve.Type?) -> String {
  match result {
    None => "Unit"
    Some(ty) => self.type_name(ty)
  }
}

///|
fn Generator::impl_type_name(self : Generator, ty : @resolve.Type) -> String {
  // Same as type_name for now
  self.type_name(ty)
}

///|
fn Generator::impl_result_type(
  self : Generator,
  result : @resolve.Type?,
) -> String {
  match result {
    None => "Unit"
    Some(ty) => self.impl_type_name(ty)
  }
}

///|
fn Generator::type_name(self : Generator, ty : @resolve.Type) -> String {
  self.type_name_with_prefix(ty, false)
}

///|
fn Generator::type_name_with_prefix(
  self : Generator,
  ty : @resolve.Type,
  use_prefix : Bool,
) -> String {
  match ty {
    Bool => "Bool"
    U8 => "Byte"
    U16 | U32 => "UInt"
    U64 => "UInt64"
    S8 | S16 | S32 => "Int"
    S64 => "Int64"
    F32 => "Float"
    F64 => "Double"
    Char => "Char"
    String_ => "String"
    Id(id) => {
      let typedef = self.resolve.types[id]
      match typedef.kind {
        List(inner) => "Array[" + self.type_name(inner) + "]"
        Option(inner) => self.type_name(inner) + "?"
        Result(ok=ok_ty, err=err_ty) => {
          let ok_str = match ok_ty {
            Some(t) => self.type_name(t)
            None => "Unit"
          }
          let err_str = match err_ty {
            Some(t) => self.type_name(t)
            None => "Unit"
          }
          "Result[" + ok_str + ", " + err_str + "]"
        }
        Tuple(types) => {
          let parts = types.map(fn(t) { self.type_name(t) })
          "(" + parts.join(", ") + ")"
        }
        _ => {
          let base_name = self.resolve_type_name_with_prefix(id, use_prefix)
          base_name
        }
      }
    }
  }
}

///|
fn Generator::resolve_type_name(self : Generator, id : Int) -> String {
  self.resolve_type_name_with_prefix(id, false)
}

///|
fn Generator::resolve_type_name_with_prefix(
  self : Generator,
  id : Int,
  use_prefix : Bool,
) -> String {
  let typedef = self.resolve.types[id]
  let base_name = match typedef.name {
    Some(name) => to_pascal_case(name)
    None => "Type" + id.to_string()
  }
  if use_prefix {
    match typedef.owner {
      Interface(iface_id) => {
        let iface = self.resolve.interfaces[iface_id]
        let pkg = iface.pkg.map(fn(pid) { self.resolve.packages[pid] })
        match pkg {
          Some(p) =>
            to_pascal_case(p.name.ns) + to_pascal_case(p.name.name) + base_name
          None => base_name
        }
      }
      World(_) | @resolve.TypeOwner::None => base_name
    }
  } else {
    base_name
  }
}

///|
fn Generator::type_to_ffi(self : Generator, ty : @resolve.Type) -> String {
  match ty {
    S8 | S16 | S32 | U8 | U16 | U32 | Bool | Char => "Int"
    S64 | U64 => "Int64"
    F32 => "Float"
    F64 => "Double"
    String_ =>
      if self.opts.use_js_string_builtins {
        "String" // Direct string type
      } else {
        "Int" // ptr
      }
    _ => "Int" // fallback
  }
}

///|
fn Generator::result_to_ffi(
  self : Generator,
  result : @resolve.Type?,
) -> String {
  match result {
    None => "Unit"
    Some(ty) => self.type_to_ffi(ty)
  }
}

///| Flat value type for canonical ABI param/result flattening
enum FlatValType {
  FlatI32
  FlatI64
  FlatF32
  FlatF64
} derive(Eq)

///| Join two flat types per canonical ABI rules
fn join_flat_type(a : FlatValType, b : FlatValType) -> FlatValType {
  if a == b {
    return a
  }
  match (a, b) {
    (FlatI32, FlatF32) | (FlatF32, FlatI32) => FlatI32
    _ => FlatI64
  }
}

///| Convert flat type to MoonBit type string
fn flat_val_type_to_moonbit(ft : FlatValType) -> String {
  match ft {
    FlatI32 => "Int"
    FlatI64 => "Int64"
    FlatF32 => "Float"
    FlatF64 => "Double"
  }
}

///| Get flat type representation for a type (canonical ABI)
fn Generator::type_flat_types(
  self : Generator,
  ty : @resolve.Type,
) -> Array[FlatValType] {
  match ty {
    Bool | U8 | S8 | U16 | S16 | U32 | S32 | Char => [FlatI32]
    U64 | S64 => [FlatI64]
    F32 => [FlatF32]
    F64 => [FlatF64]
    String_ => [FlatI32, FlatI32]
    Id(id) => {
      let typedef = self.resolve.types[id]
      match typedef.kind {
        Record(fields) => {
          let result : Array[FlatValType] = []
          for field in fields {
            for ft in self.type_flat_types(field.field_type) {
              result.push(ft)
            }
          }
          result
        }
        Variant(cases) => {
          let payload = self.variant_joined_payload(cases)
          let result : Array[FlatValType] = [FlatI32]
          for ft in payload {
            result.push(ft)
          }
          result
        }
        List(_) => [FlatI32, FlatI32]
        Enum(_) | Flags(_) => [FlatI32]
        Option(inner) => {
          let inner_flat = self.type_flat_types(inner)
          let result : Array[FlatValType] = [FlatI32]
          for ft in inner_flat {
            result.push(ft)
          }
          result
        }
        Result(ok~, err~) => {
          let payload : Array[FlatValType] = []
          match ok {
            Some(t) => {
              let flat = self.type_flat_types(t)
              for i, ft in flat {
                if i < payload.length() {
                  payload[i] = join_flat_type(payload[i], ft)
                } else {
                  payload.push(ft)
                }
              }
            }
            None => ()
          }
          match err {
            Some(t) => {
              let flat = self.type_flat_types(t)
              for i, ft in flat {
                if i < payload.length() {
                  payload[i] = join_flat_type(payload[i], ft)
                } else {
                  payload.push(ft)
                }
              }
            }
            None => ()
          }
          let result : Array[FlatValType] = [FlatI32]
          for ft in payload {
            result.push(ft)
          }
          result
        }
        Tuple(types) => {
          let result : Array[FlatValType] = []
          for t in types {
            for ft in self.type_flat_types(t) {
              result.push(ft)
            }
          }
          result
        }
        Alias(inner) => self.type_flat_types(inner)
        _ => [FlatI32]
      }
    }
  }
}

///| Get joined payload flat types for a variant's cases
fn Generator::variant_joined_payload(
  self : Generator,
  cases : Array[@resolve.VariantCase],
) -> Array[FlatValType] {
  let payload : Array[FlatValType] = []
  for case in cases {
    match case.case_type {
      Some(t) => {
        let case_flat = self.type_flat_types(t)
        for i, ft in case_flat {
          if i < payload.length() {
            payload[i] = join_flat_type(payload[i], ft)
          } else {
            payload.push(ft)
          }
        }
      }
      None => ()
    }
  }
  payload
}

///| Generate coercion expression from joined flat type to original flat type
fn coerce_flat_expr(
  expr : String,
  have : FlatValType,
  want : FlatValType,
) -> String {
  if have == want {
    return expr
  }
  match (have, want) {
    (FlatI64, FlatI32) => expr + ".to_int()"
    (FlatI64, FlatF64) => expr + ".reinterpret_as_double()"
    (FlatI64, FlatF32) =>
      "Float::from_bits(" + expr + ".to_int().reinterpret_as_uint())"
    (FlatI32, FlatF32) =>
      "Float::from_bits(" + expr + ".reinterpret_as_uint())"
    _ => expr
  }
}

///| Lift a type from flat params (for variant case payloads)
fn Generator::generate_flat_lift_expr(
  self : Generator,
  ty : @resolve.Type,
  param_base : String,
  pos : Int,
  joined : Array[FlatValType],
) -> (String, Int) {
  match ty {
    Bool => {
      let p = param_base + "_p" + pos.to_string()
      let coerced = coerce_flat_expr(p, joined[pos], FlatI32)
      (coerced + " != 0", 1)
    }
    U8 => {
      let p = param_base + "_p" + pos.to_string()
      let coerced = coerce_flat_expr(p, joined[pos], FlatI32)
      ("(" + coerced + " & 0xff).to_byte()", 1)
    }
    S8 | S16 | S32 => {
      let p = param_base + "_p" + pos.to_string()
      (coerce_flat_expr(p, joined[pos], FlatI32), 1)
    }
    U16 => {
      let p = param_base + "_p" + pos.to_string()
      let coerced = coerce_flat_expr(p, joined[pos], FlatI32)
      ("(" + coerced + " & 0xffff).reinterpret_as_uint()", 1)
    }
    U32 => {
      let p = param_base + "_p" + pos.to_string()
      let coerced = coerce_flat_expr(p, joined[pos], FlatI32)
      (coerced + ".reinterpret_as_uint()", 1)
    }
    U64 => {
      let p = param_base + "_p" + pos.to_string()
      let coerced = coerce_flat_expr(p, joined[pos], FlatI64)
      (coerced + ".reinterpret_as_uint64()", 1)
    }
    S64 => {
      let p = param_base + "_p" + pos.to_string()
      (coerce_flat_expr(p, joined[pos], FlatI64), 1)
    }
    F32 => {
      let p = param_base + "_p" + pos.to_string()
      (coerce_flat_expr(p, joined[pos], FlatF32), 1)
    }
    F64 => {
      let p = param_base + "_p" + pos.to_string()
      (coerce_flat_expr(p, joined[pos], FlatF64), 1)
    }
    Char => {
      let p = param_base + "_p" + pos.to_string()
      let coerced = coerce_flat_expr(p, joined[pos], FlatI32)
      (coerced + ".unsafe_to_char()", 1)
    }
    String_ => {
      let p0 = param_base + "_p" + pos.to_string()
      let p1 = param_base + "_p" + (pos + 1).to_string()
      let ptr_expr = coerce_flat_expr(p0, joined[pos], FlatI32)
      let len_expr = coerce_flat_expr(p1, joined[pos + 1], FlatI32)
      ("@cabi.cabi_lift_string(" + ptr_expr + ", " + len_expr + ")", 2)
    }
    Id(id) => {
      let typedef = self.resolve.types[id]
      match typedef.kind {
        Record(fields) => {
          let type_name = self.resolve_type_name(id)
          let sb = StringBuilder::new()
          sb.write_string("({ ")
          let mut consumed = 0
          for i, field in fields {
            if i > 0 {
              sb.write_string(", ")
            }
            let field_name = to_snake_case(field.name)
            let (expr, n) = self.generate_flat_lift_expr(
              field.field_type,
              param_base,
              pos + consumed,
              joined,
            )
            sb.write_string(field_name)
            sb.write_string(": ")
            sb.write_string(expr)
            consumed = consumed + n
          }
          sb.write_string(" } : ")
          sb.write_string(type_name)
          sb.write_string(")")
          (sb.to_string(), consumed)
        }
        List(_) => {
          let elem_ty = match typedef.kind {
            List(inner) => inner
            _ => abort("unreachable")
          }
          let elem_size = self.type_size(elem_ty)
          let list_type = self.type_name(Id(id))
          let p0 = param_base + "_p" + pos.to_string()
          let p1 = param_base + "_p" + (pos + 1).to_string()
          let ptr_expr = coerce_flat_expr(p0, joined[pos], FlatI32)
          let len_expr = coerce_flat_expr(p1, joined[pos + 1], FlatI32)
          let sb = StringBuilder::new()
          sb.write_string("({ let list_ptr = ")
          sb.write_string(ptr_expr)
          sb.write_string("; let list_len = ")
          sb.write_string(len_expr)
          sb.write_string("; let arr : ")
          sb.write_string(list_type)
          sb.write_string(
            " = Array::new(capacity=list_len); for i = 0; i < list_len; i = i + 1 { arr.push(",
          )
          sb.write_string(
            self.generate_list_elem_lift(
              elem_ty,
              "list_ptr + i * " + elem_size.to_string(),
            ),
          )
          sb.write_string(") }; arr })")
          (sb.to_string(), 2)
        }
        Enum(_) => {
          let type_name = self.resolve_type_name(id)
          let p = param_base + "_p" + pos.to_string()
          let coerced = coerce_flat_expr(p, joined[pos], FlatI32)
          (type_name + "::from_ordinal(" + coerced + ")", 1)
        }
        Flags(_) => {
          let type_name = self.resolve_type_name(id)
          let p = param_base + "_p" + pos.to_string()
          let coerced = coerce_flat_expr(p, joined[pos], FlatI32)
          (type_name + "::from_bits(" + coerced + ")", 1)
        }
        Option(inner) => {
          let p_disc = param_base + "_p" + pos.to_string()
          let disc_expr = coerce_flat_expr(p_disc, joined[pos], FlatI32)
          let (inner_expr, inner_consumed) = self.generate_flat_lift_expr(
            inner,
            param_base,
            pos + 1,
            joined,
          )
          (
            "(if " +
            disc_expr +
            " != 0 { Some(" +
            inner_expr +
            ") } else { None })",
            1 + inner_consumed,
          )
        }
        Alias(inner) =>
          self.generate_flat_lift_expr(inner, param_base, pos, joined)
        _ => {
          let p = param_base + "_p" + pos.to_string()
          (coerce_flat_expr(p, joined[pos], FlatI32), 1)
        }
      }
    }
  }
}
