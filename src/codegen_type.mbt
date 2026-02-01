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
fn Generator::function_trait_sig(
  self : Generator,
  func : @resolve.Function,
) -> String {
  let sb = StringBuilder::new()
  let normalized_name = normalize_func_name(func.name, func.kind)
  sb.write_string(normalized_name)
  sb.write_string("(")
  sb.write_string(self.param_list(func.params))
  sb.write_string(") -> ")
  sb.write_string(self.result_type(func.result))
  sb.to_string()
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
