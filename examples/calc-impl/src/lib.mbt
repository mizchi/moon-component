///|
/// Calculator implementation
pub(all) struct Calculator {}

///|
pub impl @calc.Exports for Calculator with add(self, a, b) {
  a + b
}

///|
fn init {
  @calc.register(Calculator::{})
}
