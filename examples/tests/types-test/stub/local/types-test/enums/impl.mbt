// Stub implementation for enums interface

///|
pub(all) struct EnumsImpl {}

///|
pub impl @exports.Exports for EnumsImpl with echo_color(_self, c : @exports.Color) -> @exports.Color {
  c
}

///|
pub impl @exports.Exports for EnumsImpl with color_name(_self, c : @exports.Color) -> String {
  match c {
    Red => "red"
    Green => "green"
    Blue => "blue"
  }
}

///|
fn init {
  @exports.register(EnumsImpl::{})
}
