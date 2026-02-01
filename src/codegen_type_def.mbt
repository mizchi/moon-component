/// Type definition generation

///|
fn Generator::generate_type_def(
  self : Generator,
  sb : StringBuilder,
  type_id : Int,
) -> Unit {
  let typedef = self.resolve.types[type_id]
  let type_name = match typedef.name {
    Some(name) => to_pascal_case(name)
    None => return // Skip anonymous types
  }
  match typedef.kind {
    Record(fields) => {
      sb.write_string("///|\n")
      sb.write_string("pub(all) struct ")
      sb.write_string(type_name)
      sb.write_string(" {\n")
      for field in fields {
        let field_name = to_snake_case(field.name)
        sb.write_string("  ")
        sb.write_string(field_name)
        sb.write_string(" : ")
        sb.write_string(self.type_name(field.field_type))
        sb.write_string("\n")
      }
      sb.write_string("} derive(Show, Eq)\n\n")
    }
    Variant(cases) => {
      sb.write_string("///|\n")
      sb.write_string("pub(all) enum ")
      sb.write_string(type_name)
      sb.write_string(" {\n")
      for case in cases {
        sb.write_string("  ")
        sb.write_string(to_pascal_case(case.name))
        match case.case_type {
          Some(t) => {
            sb.write_string("(")
            sb.write_string(self.type_name(t))
            sb.write_string(")")
          }
          None => ()
        }
        sb.write_string("\n")
      }
      sb.write_string("} derive(Show, Eq)\n\n")
    }
    Enum(cases) => {
      sb.write_string("///|\n")
      sb.write_string("pub(all) enum ")
      sb.write_string(type_name)
      sb.write_string(" {\n")
      for case in cases {
        sb.write_string("  ")
        sb.write_string(to_pascal_case(case))
        sb.write_string("\n")
      }
      sb.write_string("} derive(Show, Eq)\n\n")
      // Add from_ordinal method
      sb.write_string("///|\n")
      sb.write_string("pub fn ")
      sb.write_string(type_name)
      sb.write_string("::from_ordinal(ord : Int) -> ")
      sb.write_string(type_name)
      sb.write_string(" {\n")
      sb.write_string("  match ord {\n")
      for i, case in cases {
        sb.write_string("    ")
        sb.write_string(i.to_string())
        sb.write_string(" => ")
        sb.write_string(to_pascal_case(case))
        sb.write_string("\n")
      }
      sb.write_string("    _ => abort(\"invalid ordinal\")\n")
      sb.write_string("  }\n")
      sb.write_string("}\n\n")
      // Add ordinal method
      sb.write_string("///|\n")
      sb.write_string("pub fn ")
      sb.write_string(type_name)
      sb.write_string("::ordinal(self : ")
      sb.write_string(type_name)
      sb.write_string(") -> Int {\n")
      sb.write_string("  match self {\n")
      for i, case in cases {
        sb.write_string("    ")
        sb.write_string(to_pascal_case(case))
        sb.write_string(" => ")
        sb.write_string(i.to_string())
        sb.write_string("\n")
      }
      sb.write_string("  }\n")
      sb.write_string("}\n\n")
    }
    Flags(flags) => {
      sb.write_string("///|\n")
      sb.write_string("pub(all) struct ")
      sb.write_string(type_name)
      sb.write_string(" {\n")
      sb.write_string("  bits : UInt\n")
      sb.write_string("} derive(Show, Eq)\n\n")
      // Add from_bits method
      sb.write_string("///|\n")
      sb.write_string("pub fn ")
      sb.write_string(type_name)
      sb.write_string("::from_bits(bits : Int) -> ")
      sb.write_string(type_name)
      sb.write_string(" {\n")
      sb.write_string("  { bits: bits.reinterpret_as_uint() }\n")
      sb.write_string("}\n\n")
      // Add to_bits method
      sb.write_string("///|\n")
      sb.write_string("pub fn ")
      sb.write_string(type_name)
      sb.write_string("::to_bits(self : ")
      sb.write_string(type_name)
      sb.write_string(") -> Int {\n")
      sb.write_string("  self.bits.reinterpret_as_int()\n")
      sb.write_string("}\n\n")
      // Add flag constants
      for i, flag in flags {
        sb.write_string("///|\n")
        sb.write_string("pub const ")
        sb.write_string(to_pascal_case(flag))
        sb.write_string(" : ")
        sb.write_string(type_name)
        sb.write_string(" = { bits: ")
        sb.write_string((1U << i).to_string())
        sb.write_string(" }\n\n")
      }
    }
    Resource => {
      // Resource type: newtype wrapper around Int (handle)
      sb.write_string("///|\n")
      sb.write_string("pub(all) struct ")
      sb.write_string(type_name)
      sb.write_string("(Int) derive(Show, Eq)\n\n")
    }
    _ => () // Skip other types for now
  }
}
