///|
test "wasmExportAdd works" {
  // Initialize
  @calc.register(Calculator::{})

  // Test via FFI wrapper
  let result = @calc.wasmExportAdd(1, 2)
  inspect(result, content="3")
}
