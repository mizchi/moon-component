// Canonical ABI helpers for testing

///|
/// Linear memory buffer for canonical ABI
let cabi_memory : Array[Byte] = Array::make(65536, b'\x00')

///|
/// Current allocation offset
let cabi_offset : Ref[Int] = { val: 0 }

///|
/// Canonical ABI realloc function
pub fn cabi_realloc(
  old_ptr : Int,
  old_size : Int,
  align : Int,
  new_size : Int,
) -> Int {
  // Align offset
  let aligned = (cabi_offset.val + align - 1) & -align
  // Grow buffer if needed
  while aligned + new_size > cabi_memory.length() {
    cabi_memory.push(b'\x00')
  }
  // Copy old data if reallocating
  if old_ptr != 0 && old_size > 0 {
    for i in 0..<old_size {
      cabi_memory[aligned + i] = cabi_memory[old_ptr + i]
    }
  }
  cabi_offset.val = aligned + new_size
  aligned
}

///|
/// Reset the allocator
pub fn cabi_reset() -> Unit {
  cabi_offset.val = 0
  // Clear memory for clean tests
  for i in 0..<cabi_memory.length() {
    cabi_memory[i] = b'\x00'
  }
}

///|
/// Lift a string from linear memory
pub fn cabi_lift_string(ptr : Int, len : Int) -> String {
  let bytes : Array[Byte] = []
  for i in 0..<len {
    bytes.push(cabi_memory[ptr + i])
  }
  @utf8.decode_lossy(Bytes::from_array(bytes[:])[:])
}

///|
/// Lower a string to linear memory
pub fn cabi_lower_string(s : String) -> (Int, Int) {
  let bytes = @utf8.encode(s)
  let len = bytes.length()
  let ptr = cabi_realloc(0, 0, 1, len)
  for i in 0..<len {
    cabi_memory[ptr + i] = bytes[i]
  }
  (ptr, len)
}

///|
/// Read i32 from linear memory
pub fn cabi_read_i32(ptr : Int) -> Int {
  let b0 = cabi_memory[ptr].to_int()
  let b1 = cabi_memory[ptr + 1].to_int()
  let b2 = cabi_memory[ptr + 2].to_int()
  let b3 = cabi_memory[ptr + 3].to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
/// Write i32 to linear memory
pub fn cabi_write_i32(ptr : Int, val : Int) -> Unit {
  cabi_memory[ptr] = (val & 0xff).to_byte()
  cabi_memory[ptr + 1] = ((val >> 8) & 0xff).to_byte()
  cabi_memory[ptr + 2] = ((val >> 16) & 0xff).to_byte()
  cabi_memory[ptr + 3] = ((val >> 24) & 0xff).to_byte()
}

///|
/// Get memory for direct byte access
pub fn cabi_get_memory() -> Array[Byte] {
  cabi_memory
}

///|
/// Read i64 from linear memory
pub fn cabi_read_i64(ptr : Int) -> Int64 {
  let lo = cabi_read_i32(ptr).to_int64()
  let hi = cabi_read_i32(ptr + 4).to_int64()
  lo | (hi << 32)
}

///|
/// Write i64 to linear memory
pub fn cabi_write_i64(ptr : Int, val : Int64) -> Unit {
  cabi_write_i32(ptr, val.to_int())
  cabi_write_i32(ptr + 4, (val >> 32).to_int())
}

///|
/// Read f32 from linear memory
pub fn cabi_read_f32(ptr : Int) -> Float {
  Float::reinterpret_from_int(cabi_read_i32(ptr))
}

///|
/// Write f32 to linear memory
pub fn cabi_write_f32(ptr : Int, val : Float) -> Unit {
  cabi_write_i32(ptr, val.reinterpret_as_int())
}

///|
/// Read f64 from linear memory
pub fn cabi_read_f64(ptr : Int) -> Double {
  cabi_read_i64(ptr).reinterpret_as_double()
}

///|
/// Write f64 to linear memory
pub fn cabi_write_f64(ptr : Int, val : Double) -> Unit {
  cabi_write_i64(ptr, val.reinterpret_as_int64())
}

///|
/// Get current offset
pub fn cabi_get_offset() -> Int {
  cabi_offset.val
}
