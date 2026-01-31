// User implementation - edit this file
// This file will not be overwritten on regeneration

///|
pub(all) struct ApiImpl {}

///|
pub impl Exports for ApiImpl with calc_add(_self, a : Int, b : Int) -> Int {
  @math.add(a, b)
}

///|
pub impl Exports for ApiImpl with calc_factorial(_self, n : UInt) -> UInt64 {
  @math.factorial(n)
}

///|
pub impl Exports for ApiImpl with calc_multiply(_self, a : Int, b : Int) -> Int {
  @math.multiply(a, b)
}

///|
pub impl Exports for ApiImpl with describe_factorial(_self, n : UInt) -> String {
  let result = @math.factorial(n)
  let msg = n.to_string() + "! = " + result.to_string()
  @strings.uppercase(msg)
}

///|
pub impl Exports for ApiImpl with str_repeat(_self, s : String, n : UInt) -> String {
  @strings.repeat(s, n)
}

///|
pub impl Exports for ApiImpl with str_reverse(_self, s : String) -> String {
  @strings.reverse(s)
}

///|
pub impl Exports for ApiImpl with str_uppercase(_self, s : String) -> String {
  @strings.uppercase(s)
}

///|
fn init {
  register(ApiImpl::{})
}
