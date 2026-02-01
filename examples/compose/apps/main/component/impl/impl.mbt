// User implementation - edit this file
// This file will not be overwritten on regeneration

///|
pub fn calc_add(a : Int, b : Int) -> Int {
  @math.add(a, b)
}

///|
pub fn calc_factorial(n : UInt) -> UInt64 {
  @math.factorial(n)
}

///|
pub fn calc_multiply(a : Int, b : Int) -> Int {
  @math.multiply(a, b)
}

///|
pub fn describe_factorial(n : UInt) -> String {
  let result = @math.factorial(n)
  let msg = n.to_string() + "! = " + result.to_string()
  @strings.uppercase(msg)
}

///|
pub fn str_repeat(s : String, n : UInt) -> String {
  @strings.repeat(s, n)
}

///|
pub fn str_reverse(s : String) -> String {
  @strings.reverse(s)
}

///|
pub fn str_uppercase(s : String) -> String {
  @strings.uppercase(s)
}
