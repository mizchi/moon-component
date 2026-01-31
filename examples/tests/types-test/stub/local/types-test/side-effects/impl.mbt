// Stub implementation for side-effects interface

///|
pub(all) struct SideEffectsImpl {}

///|
pub impl @exports.Exports for SideEffectsImpl with no_return(_self, _msg : String) -> Unit {
  // Side effect: do nothing
}

///|
pub impl @exports.Exports for SideEffectsImpl with no_params_no_return(_self) -> Unit {
  // No-op
}

///|
fn init {
  @exports.register(SideEffectsImpl::{})
}
