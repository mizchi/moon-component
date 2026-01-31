// Stub implementation for multi-params interface

///|
pub(all) struct MultiParamsImpl {}

///|
pub impl @exports.Exports for MultiParamsImpl with add2(_self, a : Int, b : Int) -> Int {
  a + b
}

///|
pub impl @exports.Exports for MultiParamsImpl with add3(_self, a : Int, b : Int, c : Int) -> Int {
  a + b + c
}

///|
pub impl @exports.Exports for MultiParamsImpl with add4(_self, a : Int, b : Int, c : Int, d : Int) -> Int {
  a + b + c + d
}

///|
pub impl @exports.Exports for MultiParamsImpl with concat3(_self, a : String, b : String, c : String) -> String {
  a + b + c
}

///|
pub impl @exports.Exports for MultiParamsImpl with mixed_params(_self, n : Int, s : String, b : Bool) -> String {
  let bool_str = if b { "true" } else { "false" }
  n.to_string() + ":" + s + ":" + bool_str
}

///|
fn init {
  @exports.register(MultiParamsImpl::{})
}
