///|
fn ffi_get_stdout() -> Int = "wasi:cli/stdout@0.2.9" "get-stdout"

///|
fn ffi_output_stream_blocking_write_and_flush(
  stream : Int,
  bytes_ptr : Int,
  bytes_len : Int,
  retptr : Int,
) -> Int = "wasi:io/streams@0.2.9" "[method]output-stream.blocking-write-and-flush"

///|
/// Write WAGI-compatible HTTP response bytes to stdout.
fn write_stdout(content : String) -> Bool {
  let stream = ffi_get_stdout()
  let (bytes_ptr, bytes_len) = @cabi.cabi_lower_string(content)
  let retptr = @cabi.cabi_realloc(0, 0, 4, 12)
  let _ = ffi_output_stream_blocking_write_and_flush(
    stream, bytes_ptr, bytes_len, retptr,
  )
  @cabi.cabi_read_i32(retptr) == 0
}

///|
pub fn run() -> Result[Unit, Unit] {
  let response = "Content-Type: text/plain\nStatus: 200\n\nhello from moon-component (WASIp2 + WAGI)\n"
  if write_stdout(response) {
    Ok(())
  } else {
    Err(())
  }
}
