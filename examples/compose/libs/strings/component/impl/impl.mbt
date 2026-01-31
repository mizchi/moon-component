// Strings library implementation

///|
pub(all) struct UtilsImpl {}

///|
pub impl Exports for UtilsImpl with reverse(_self, s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  let result = StringBuilder::new()
  for i = len - 1; i >= 0; i = i - 1 {
    result.write_char(chars[i])
  }
  result.to_string()
}

///|
pub impl Exports for UtilsImpl with uppercase(_self, s : String) -> String {
  let result = StringBuilder::new()
  for c in s {
    let upper = if c >= 'a' && c <= 'z' {
      Char::from_int(c.to_int() - 32)
    } else {
      c
    }
    result.write_char(upper)
  }
  result.to_string()
}

///|
pub impl Exports for UtilsImpl with repeat(_self, s : String, n : UInt) -> String {
  let result = StringBuilder::new()
  for i = 0; i < n.reinterpret_as_int(); i = i + 1 {
    result.write_string(s)
  }
  result.to_string()
}

///|
fn init {
  register(UtilsImpl::{})
}
