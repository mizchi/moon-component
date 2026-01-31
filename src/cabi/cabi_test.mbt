///|
/// Test cabi_realloc basic allocation
test "cabi_realloc_basic" {
  cabi_reset()

  // Allocate 10 bytes
  let ptr1 = cabi_realloc(0, 0, 1, 10)
  inspect(ptr1, content="0")
  inspect(cabi_get_offset(), content="10")

  // Allocate another 10 bytes
  let ptr2 = cabi_realloc(0, 0, 1, 10)
  inspect(ptr2, content="10")
  inspect(cabi_get_offset(), content="20")
}

///|
/// Test cabi_realloc with alignment
test "cabi_realloc_alignment" {
  cabi_reset()

  // Allocate 1 byte
  let ptr1 = cabi_realloc(0, 0, 1, 1)
  inspect(ptr1, content="0")

  // Allocate with 4-byte alignment
  let ptr2 = cabi_realloc(0, 0, 4, 4)
  inspect(ptr2, content="4") // aligned to 4

  // Allocate with 8-byte alignment
  let ptr3 = cabi_realloc(0, 0, 8, 8)
  inspect(ptr3, content="8") // aligned to 8
}

///|
/// Test cabi_write_i32 and cabi_read_i32
test "cabi_i32_roundtrip" {
  cabi_reset()

  // Test various values
  cabi_write_i32(0, 0)
  inspect(cabi_read_i32(0), content="0")
  cabi_write_i32(0, 1)
  inspect(cabi_read_i32(0), content="1")
  cabi_write_i32(0, 255)
  inspect(cabi_read_i32(0), content="255")
  cabi_write_i32(0, 256)
  inspect(cabi_read_i32(0), content="256")
  cabi_write_i32(0, 65535)
  inspect(cabi_read_i32(0), content="65535")
  cabi_write_i32(0, 0x12345678)
  inspect(cabi_read_i32(0), content="305419896")

  // Test negative numbers (two's complement)
  cabi_write_i32(0, -1)
  inspect(cabi_read_i32(0), content="-1")
  cabi_write_i32(0, -256)
  inspect(cabi_read_i32(0), content="-256")
}

///|
/// Test cabi_write_i64 and cabi_read_i64
test "cabi_i64_roundtrip" {
  cabi_reset()
  cabi_write_i64(0, 0L)
  inspect(cabi_read_i64(0), content="0")
  cabi_write_i64(0, 1L)
  inspect(cabi_read_i64(0), content="1")
  cabi_write_i64(0, 0x123456789ABCDEF0L)
  inspect(cabi_read_i64(0), content="-1698898192")
  cabi_write_i64(0, -1L)
  inspect(cabi_read_i64(0), content="-1")
}

///|
/// Test cabi_write_f32 and cabi_read_f32
test "cabi_f32_roundtrip" {
  cabi_reset()
  cabi_write_f32(0, 0.0)
  inspect(cabi_read_f32(0), content="0")
  cabi_write_f32(0, 1.0)
  inspect(cabi_read_f32(0), content="1")
  cabi_write_f32(0, 3.14)
  // Float precision
  let val = cabi_read_f32(0)
  inspect(val > 3.13 && val < 3.15, content="true")
  cabi_write_f32(0, -1.5)
  inspect(cabi_read_f32(0), content="-1.5")
}

///|
/// Test cabi_write_f64 and cabi_read_f64
test "cabi_f64_roundtrip" {
  cabi_reset()
  cabi_write_f64(0, 0.0)
  inspect(cabi_read_f64(0), content="0")
  cabi_write_f64(0, 1.0)
  inspect(cabi_read_f64(0), content="1")
  cabi_write_f64(0, 3.141592653589793)
  inspect(cabi_read_f64(0), content="3.141592653589793")
  cabi_write_f64(0, -1.5)
  inspect(cabi_read_f64(0), content="-1.5")
}

///|
/// Test cabi_lower_string and cabi_lift_string
test "cabi_string_roundtrip" {
  cabi_reset()

  // Test empty string
  let (ptr1, len1) = cabi_lower_string("")
  inspect(len1, content="0")
  inspect(cabi_lift_string(ptr1, len1), content="")

  // Test simple string (UTF-8: 5 bytes for "hello")
  cabi_reset()
  let (ptr2, len2) = cabi_lower_string("hello")
  inspect(len2, content="5")
  inspect(cabi_lift_string(ptr2, len2), content="hello")

  // Test unicode string (UTF-8: 3 bytes per Japanese character = 15 bytes)
  cabi_reset()
  let (ptr3, len3) = cabi_lower_string("こんにちは")
  inspect(len3, content="15")
  inspect(cabi_lift_string(ptr3, len3), content="こんにちは")

  // Test string with spaces (UTF-8: 11 bytes)
  cabi_reset()
  let (ptr4, len4) = cabi_lower_string("hello world")
  inspect(len4, content="11")
  inspect(cabi_lift_string(ptr4, len4), content="hello world")
}

///|
/// Test multiple strings in memory
test "cabi_multiple_strings" {
  cabi_reset()
  let (ptr1, len1) = cabi_lower_string("first")
  let (ptr2, len2) = cabi_lower_string("second")
  let (ptr3, len3) = cabi_lower_string("third")

  // All strings should be retrievable
  inspect(cabi_lift_string(ptr1, len1), content="first")
  inspect(cabi_lift_string(ptr2, len2), content="second")
  inspect(cabi_lift_string(ptr3, len3), content="third")

  // Pointers should not overlap
  inspect(ptr2 >= ptr1 + len1, content="true")
  inspect(ptr3 >= ptr2 + len2, content="true")
}

///|
/// Test record-like structure in memory
test "cabi_record_simulation" {
  cabi_reset()

  // Simulate Point { x: i32, y: i32 }
  let ptr = cabi_realloc(0, 0, 4, 8)

  // Write x = 10, y = 20
  cabi_write_i32(ptr, 10)
  cabi_write_i32(ptr + 4, 20)

  // Read back
  inspect(cabi_read_i32(ptr), content="10")
  inspect(cabi_read_i32(ptr + 4), content="20")
}

///|
/// Test variant-like structure in memory
test "cabi_variant_simulation" {
  cabi_reset()

  // Simulate Shape variant
  // Case 0: Circle(i32) - discriminant=0, payload=radius
  // Case 1: Rectangle(Point) - discriminant=1, payload=Point
  // Case 2: None - discriminant=2, no payload

  let ptr = cabi_realloc(0, 0, 4, 12) // max size

  // Write Circle(5)
  cabi_write_i32(ptr, 0) // discriminant
  cabi_write_i32(ptr + 4, 5) // radius
  inspect(cabi_read_i32(ptr), content="0")
  inspect(cabi_read_i32(ptr + 4), content="5")

  // Write Rectangle(Point{x:10, y:20})
  cabi_write_i32(ptr, 1) // discriminant
  cabi_write_i32(ptr + 4, 10) // x
  cabi_write_i32(ptr + 8, 20) // y
  inspect(cabi_read_i32(ptr), content="1")
  inspect(cabi_read_i32(ptr + 4), content="10")
  inspect(cabi_read_i32(ptr + 8), content="20")

  // Write None
  cabi_write_i32(ptr, 2) // discriminant
  inspect(cabi_read_i32(ptr), content="2")
}

///|
/// Test option-like structure in memory
test "cabi_option_simulation" {
  cabi_reset()

  // Simulate Option<i32>
  // None: discriminant=0
  // Some(v): discriminant=1, payload=v

  let ptr = cabi_realloc(0, 0, 4, 8)

  // Write None
  cabi_write_i32(ptr, 0)
  inspect(cabi_read_i32(ptr), content="0")

  // Write Some(42)
  cabi_write_i32(ptr, 1)
  cabi_write_i32(ptr + 4, 42)
  inspect(cabi_read_i32(ptr), content="1")
  inspect(cabi_read_i32(ptr + 4), content="42")
}

///|
/// Test result-like structure in memory
test "cabi_result_simulation" {
  cabi_reset()

  // Simulate Result<i32, String>
  // Ok(v): discriminant=0, payload=v
  // Err(s): discriminant=1, payload=(ptr, len)

  let ptr = cabi_realloc(0, 0, 4, 12)

  // Write Ok(100)
  cabi_write_i32(ptr, 0)
  cabi_write_i32(ptr + 4, 100)
  inspect(cabi_read_i32(ptr), content="0")
  inspect(cabi_read_i32(ptr + 4), content="100")

  // Write Err("error")
  let (str_ptr, str_len) = cabi_lower_string("error")
  cabi_write_i32(ptr, 1)
  cabi_write_i32(ptr + 4, str_ptr)
  cabi_write_i32(ptr + 8, str_len)
  inspect(cabi_read_i32(ptr), content="1")
  let err_ptr = cabi_read_i32(ptr + 4)
  let err_len = cabi_read_i32(ptr + 8)
  inspect(cabi_lift_string(err_ptr, err_len), content="error")
}

///|
/// Test list-like structure in memory
test "cabi_list_simulation" {
  cabi_reset()

  // Simulate List<i32> with 3 elements: [10, 20, 30]
  let elem_size = 4
  let count = 3
  let list_ptr = cabi_realloc(0, 0, 4, count * elem_size)

  // Write elements
  cabi_write_i32(list_ptr, 10)
  cabi_write_i32(list_ptr + 4, 20)
  cabi_write_i32(list_ptr + 8, 30)

  // Read elements
  inspect(cabi_read_i32(list_ptr), content="10")
  inspect(cabi_read_i32(list_ptr + 4), content="20")
  inspect(cabi_read_i32(list_ptr + 8), content="30")

  // Store list as (ptr, len)
  let ret_ptr = cabi_realloc(0, 0, 4, 8)
  cabi_write_i32(ret_ptr, list_ptr)
  cabi_write_i32(ret_ptr + 4, count)

  // Read list metadata
  inspect(cabi_read_i32(ret_ptr), content=list_ptr.to_string())
  inspect(cabi_read_i32(ret_ptr + 4), content="3")
}

///|
/// Test flags-like bitmask operations
test "cabi_flags_simulation" {
  cabi_reset()

  // Simulate Flags { read, write, execute }
  // read = bit 0, write = bit 1, execute = bit 2

  let ptr = cabi_realloc(0, 0, 4, 4)

  // No flags set
  cabi_write_i32(ptr, 0)
  inspect(cabi_read_i32(ptr) & 1, content="0") // read
  inspect(cabi_read_i32(ptr) & 2, content="0") // write
  inspect(cabi_read_i32(ptr) & 4, content="0") // execute

  // Read only
  cabi_write_i32(ptr, 1)
  inspect((cabi_read_i32(ptr) & 1) != 0, content="true")
  inspect((cabi_read_i32(ptr) & 2) != 0, content="false")

  // Read + write
  cabi_write_i32(ptr, 3)
  inspect((cabi_read_i32(ptr) & 1) != 0, content="true")
  inspect((cabi_read_i32(ptr) & 2) != 0, content="true")
  inspect((cabi_read_i32(ptr) & 4) != 0, content="false")

  // All flags
  cabi_write_i32(ptr, 7)
  inspect((cabi_read_i32(ptr) & 1) != 0, content="true")
  inspect((cabi_read_i32(ptr) & 2) != 0, content="true")
  inspect((cabi_read_i32(ptr) & 4) != 0, content="true")
}

///|
/// Test byte-level memory access
test "cabi_byte_access" {
  cabi_reset()
  let mem = cabi_get_memory()

  // Write individual bytes (ASCII)
  mem[0] = b'\x41' // 'A'
  mem[1] = b'\x42' // 'B'
  mem[2] = b'\x43' // 'C'
  inspect(mem[0], content="b'\\x41'")
  inspect(mem[1], content="b'\\x42'")
  inspect(mem[2], content="b'\\x43'")

  // Read as UTF-8 string
  let s = cabi_lift_string(0, 3)
  inspect(s, content="ABC")
}
