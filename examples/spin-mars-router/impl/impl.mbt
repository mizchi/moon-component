///|
fn ffi_get_arguments(retptr : Int) -> Int = "wasi:cli/environment@0.2.9" "get-arguments"

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
fn read_arguments() -> Array[String] {
  let retptr = @cabi.cabi_realloc(0, 0, 4, 8)
  let _ = ffi_get_arguments(retptr)
  let result_ptr = @cabi.cabi_read_i32(retptr)
  let result_len = @cabi.cabi_read_i32(retptr + 4)
  let arr = Array::new(capacity=result_len)
  for i = 0; i < result_len; i = i + 1 {
    let elem_ptr = result_ptr + i * 8
    let ptr = @cabi.cabi_read_i32(elem_ptr)
    let len = @cabi.cabi_read_i32(elem_ptr + 4)
    arr.push(@cabi.cabi_lift_string(ptr, len))
  }
  arr
}

///|
fn path_from_arguments() -> String {
  let args = read_arguments()
  for i = 0; i < args.length(); i = i + 1 {
    let arg = args[i]
    if arg.has_prefix("/") {
      if arg == "" {
        return "/"
      } else {
        return arg
      }
    }
  }
  "/"
}

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
fn render_wagi_response(status : Int, body : String) -> String {
  "Content-Type: text/plain\nStatus: " +
  status.to_string() +
  "\n\n" +
  body +
  "\n"
}

///|
pub fn run() -> Result[Unit, Unit] {
  let path = path_from_arguments()
  let routed = @app.route("GET", path)
  let response = render_wagi_response(routed.status, routed.body)
  let _ = write_stdout(response)
  Ok(())
}
