// Math library implementation

///|
pub fn add(a : Int, b : Int) -> Int {
  a + b
}

///|
pub fn multiply(a : Int, b : Int) -> Int {
  a * b
}

///|
pub fn factorial(n : UInt) -> UInt64 {
  fn fact(n : UInt64) -> UInt64 {
    if n <= 1UL {
      1UL
    } else {
      n * fact(n - 1UL)
    }
  }
  fact(n.to_uint64())
}
