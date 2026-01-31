// User implementation - edit this file
// This file will not be overwritten on regeneration

///|
pub(all) struct GreetImpl {}

///|
pub impl Exports for GreetImpl with greet(self, name : String) -> String {
  let _ = self
  // TODO: implement
  abort("not implemented")
}

///|
fn init {
  register(GreetImpl::{})
}
