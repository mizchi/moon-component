// Stub implementation - edit this file
// This file will not be overwritten on regeneration

// Import: import-test/gen/interface/local/import-test/greet-consumer

///|
pub(all) struct GreetConsumerImpl {}

///|
pub impl @exports.Exports for GreetConsumerImpl with run(_self) -> String {
  // Call the imported get_greeting function
  @greet_provider.get_greeting("MoonBit")
}

///|
fn init {
  @exports.register(GreetConsumerImpl::{})
}
