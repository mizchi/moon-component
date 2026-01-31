// Stub implementation for flags-test interface

///|
pub(all) struct FlagsTestImpl {}

///|
pub impl @exports.Exports for FlagsTestImpl with echo_permissions(_self, p : @exports.Permissions) -> @exports.Permissions {
  p
}

///|
pub impl @exports.Exports for FlagsTestImpl with has_read(_self, p : @exports.Permissions) -> Bool {
  p.read
}

///|
pub impl @exports.Exports for FlagsTestImpl with has_write(_self, p : @exports.Permissions) -> Bool {
  p.write
}

///|
fn init {
  @exports.register(FlagsTestImpl::{})
}
