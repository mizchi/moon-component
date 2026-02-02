// User implementation for world host
// Edit this file to implement the world exports

///|
/// Export: run
pub fn run(pattern : String, text : String, replacement : String) -> String {
  if @regex.is_match(pattern, text) {
    @regex.replace(pattern, text, replacement)
  } else {
    text
  }
}
