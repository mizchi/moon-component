// User implementation for run
// Edit this file to implement the interface

///|
/// Export: run
pub fn run() -> Result[Unit, Unit] {
  let args = @env.get_arguments()
  if args.length() >= 2 {
    Ok(())
  } else {
    Err(())
  }
}
