// Strings library implementation

///|
pub fn reverse(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  let result = StringBuilder::new()
  for i = len - 1; i >= 0; i = i - 1 {
    result.write_char(chars[i])
  }
  result.to_string()
}

///|
pub fn uppercase(s : String) -> String {
  let result = StringBuilder::new()
  for c in s {
    let upper = if c >= 'a' && c <= 'z' {
      (c.to_int() - 32).unsafe_to_char()
    } else {
      c
    }
    result.write_char(upper)
  }
  result.to_string()
}

///|
pub fn repeat(s : String, n : UInt) -> String {
  let result = StringBuilder::new()
  for i = 0; i < n.reinterpret_as_int(); i = i + 1 {
    result.write_string(s)
  }
  result.to_string()
}
