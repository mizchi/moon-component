// Native FFI functions for subprocess execution

///|
#borrow(cmd)
extern "C" fn c_main_system(cmd : Bytes) -> Int = "mc_system_ffi"

///|
fn to_c_string(s : String) -> Bytes {
  let buf : Array[Byte] = []
  let len = s.length()
  let mut i = 0
  while i < len {
    let mut c = s.code_unit_at(i).to_int()
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < len {
      let lo = s.code_unit_at(i + 1).to_int() - 0xDC00
      c = ((c - 0xD800) << 10) + lo + 0x10000
      buf.push((0xF0 | (c >> 18)).to_byte())
      buf.push((0x80 | ((c >> 12) & 0x3F)).to_byte())
      buf.push((0x80 | ((c >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (c & 0x3F)).to_byte())
      i += 2
    } else if c < 0x80 {
      buf.push(c.to_byte())
      i += 1
    } else if c < 0x800 {
      buf.push((0xC0 | (c >> 6)).to_byte())
      buf.push((0x80 | (c & 0x3F)).to_byte())
      i += 1
    } else {
      buf.push((0xE0 | (c >> 12)).to_byte())
      buf.push((0x80 | ((c >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (c & 0x3F)).to_byte())
      i += 1
    }
  }
  buf.push(b'\x00')
  Bytes::from_array(buf)
}

///|
fn shell_quote(s : String) -> String {
  let buf : Array[Char] = ['\'']
  for ch in s {
    if ch == '\'' {
      buf..push('\'')..push('\\')..push('\'').push('\'')
    } else {
      buf.push(ch)
    }
  }
  buf.push('\'')
  String::from_array(buf)
}

///|
fn run_shell_cmd(cmd : String) -> Int {
  let cmd_bytes = to_c_string(cmd)
  c_main_system(cmd_bytes)
}
