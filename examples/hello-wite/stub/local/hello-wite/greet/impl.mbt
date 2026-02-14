// Stub implementation

///|
pub(all) struct GreetImpl {}

///|
pub impl @exports.Exports for GreetImpl with greet(_self, name : String) -> String {
  "Hello, " + name + "!"
}

///|
fn init {
  @exports.register(GreetImpl::{})
}
