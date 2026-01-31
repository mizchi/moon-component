// Stub implementation for containers interface

///|
pub(all) struct ContainersImpl {}

///|
pub impl @exports.Exports for ContainersImpl with sum_list(_self, vals : Array[Int]) -> Int {
  let mut sum = 0
  for v in vals {
    sum = sum + v
  }
  sum
}

///|
pub impl @exports.Exports for ContainersImpl with echo_list_s64(_self, vals : Array[Int64]) -> Array[Int64] {
  vals
}

///|
pub impl @exports.Exports for ContainersImpl with count_list(_self, vals : Array[String]) -> Int {
  vals.length()
}

///|
pub impl @exports.Exports for ContainersImpl with divide(_self, a : Int, b : Int) -> Result[Int, String] {
  if b == 0 {
    Err("division by zero")
  } else {
    Ok(a / b)
  }
}

///|
fn init {
  @exports.register(ContainersImpl::{})
}
