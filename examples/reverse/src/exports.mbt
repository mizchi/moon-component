// User-defined exports - will be converted to WIT

///| Point record
pub(all) struct Point {
  x : Int
  y : Int
}

///| Color enum (const-only, no payload)
pub(all) enum Color {
  Red
  Green
  Blue
  Yellow
  Cyan
  Magenta
}

///| Export trait - defines the component interface
pub(open) trait Exports {
  // Simple greeting
  greet(Self, name : String) -> String

  // Arithmetic
  add(Self, a : Int, b : Int) -> Int

  // Boolean
  is_even(Self, n : Int) -> Bool

  // Optional
  find_user(Self, id : Int) -> String?

  // Result
  parse_int(Self, s : String) -> Result[Int, String]

  // Record
  create_point(Self, x : Int, y : Int) -> Point

  // Enum
  get_color(Self, name : String) -> Color

  // List
  sum_list(Self, nums : Array[Int]) -> Int
}
