// Math library implementation

///|
pub(all) struct OperationsImpl {}

///|
pub impl Exports for OperationsImpl with add(_self, a : Int, b : Int) -> Int {
  a + b
}

///|
pub impl Exports for OperationsImpl with multiply(_self, a : Int, b : Int) -> Int {
  a * b
}

///|
pub impl Exports for OperationsImpl with factorial(_self, n : UInt) -> UInt64 {
  fn fact(n : UInt64) -> UInt64 {
    if n <= 1UL {
      1UL
    } else {
      n * fact(n - 1UL)
    }
  }
  fact(n.to_uint64())
}

///|
fn init {
  register(OperationsImpl::{})
}
