// Stub implementation for primitives interface

///|
pub(all) struct PrimitivesImpl {}

///|
pub impl @exports.Exports for PrimitivesImpl with echo_bool(_self, val : Bool) -> Bool {
  val
}

///|
pub impl @exports.Exports for PrimitivesImpl with echo_f32(_self, val : Float) -> Float {
  val
}

///|
pub impl @exports.Exports for PrimitivesImpl with echo_f64(_self, val : Double) -> Double {
  val
}

///|
pub impl @exports.Exports for PrimitivesImpl with echo_s32(_self, val : Int) -> Int {
  val
}

///|
pub impl @exports.Exports for PrimitivesImpl with echo_s64(_self, val : Int64) -> Int64 {
  val
}

///|
pub impl @exports.Exports for PrimitivesImpl with echo_string(_self, val : String) -> String {
  val
}

///|
fn init {
  @exports.register(PrimitivesImpl::{})
}
