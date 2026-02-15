// componentize command: create a wasm component from a core wasm module
// Handles retptr import patching automatically

///|
fn cmd_componentize(args : Array[String]) -> Unit {
  // Parse arguments
  let mut input_path : String? = None
  let mut wit_path : String? = None
  let mut world_name : String? = None
  let mut output_path : String? = None
  let mut i = 2
  while i < args.length() {
    if args[i] == "--wit" && i + 1 < args.length() {
      wit_path = Some(args[i + 1])
      i = i + 2
    } else if args[i] == "--world" && i + 1 < args.length() {
      world_name = Some(args[i + 1])
      i = i + 2
    } else if (args[i] == "-o" || args[i] == "--output") &&
      i + 1 < args.length() {
      output_path = Some(args[i + 1])
      i = i + 2
    } else if args[i].has_prefix("--") {
      println("Unknown option: " + args[i])
      componentize_usage()
      @sys.exit(1)
    } else {
      input_path = Some(args[i])
      i = i + 1
    }
  }
  guard input_path is Some(input) else {
    componentize_usage()
    @sys.exit(1)
  }
  guard wit_path is Some(wit) else {
    println("Error: --wit is required")
    componentize_usage()
    @sys.exit(1)
  }
  guard output_path is Some(output) else {
    println("Error: -o is required")
    componentize_usage()
    @sys.exit(1)
  }

  // Resolve WIT
  let resolved_result : Result[@wit.ResolveInput, @wit.ParseError] = match
    world_name {
    Some(name) => @wit.resolve_path(wit, world=name)
    None => @wit.resolve_path(wit)
  }
  let resolved = match resolved_result {
    Ok(v) => v
    Err(e) => {
      println("Error resolving WIT: " + e.to_string())
      @sys.exit(1)
      abort("exit")
    }
  }
  let json = resolved.to_json()
  let resolve_input : @resolve.ResolveInput = @json.from_json(json) catch {
    e => {
      println("Error decoding ResolveInput: " + e.to_string())
      @sys.exit(1)
      abort("exit")
    }
  }

  // Detect retptr imports
  let opts = @codegen.GeneratorOpts::default()
  let gen = @codegen.Generator::new(
    resolve_input.resolve,
    resolve_input.world_id,
    opts,
  )
  let retptr_imports = gen.detect_retptr_imports()

  // Build world name for wasm-tools
  let world_arg = match world_name {
    Some(name) => name
    None => {
      let world = resolve_input.resolve.worlds[resolve_input.world_id]
      world.name
    }
  }

  let tmpdir = @sys.get_env_var("TMPDIR").unwrap_or("/tmp")
  let tmp_prefix = tmpdir + "/mc-componentize"

  if retptr_imports.length() > 0 {
    // Need WAT patching
    println(
      "Detected " +
      retptr_imports.length().to_string() +
      " retptr import(s), applying WAT patch...",
    )

    let wat_path = tmp_prefix + ".wat"
    let patched_wat_path = tmp_prefix + "-patched.wat"
    let patched_wasm_path = tmp_prefix + "-patched.wasm"
    let embedded_path = tmp_prefix + "-embedded.wasm"

    // wasm-tools print
    let rc = run_shell_cmd(
      "wasm-tools print " + shell_quote(input) + " > " + shell_quote(wat_path),
    )
    if rc != 0 {
      println("Error: wasm-tools print failed (exit " + rc.to_string() + ")")
      @sys.exit(1)
    }

    // Read WAT, apply patches
    let wat_content = @fs.read_file_to_string(wat_path) catch {
      e => {
        println("Error reading WAT: " + e.to_string())
        @sys.exit(1)
        abort("exit")
      }
    }
    let patched = patch_wat(wat_content, retptr_imports)
    @fs.write_string_to_file(patched_wat_path, patched) catch {
      e => {
        println("Error writing patched WAT: " + e.to_string())
        @sys.exit(1)
        abort("exit")
      }
    }

    // wasm-tools parse
    let rc2 = run_shell_cmd(
      "wasm-tools parse " +
      shell_quote(patched_wat_path) +
      " -o " +
      shell_quote(patched_wasm_path),
    )
    if rc2 != 0 {
      println("Error: wasm-tools parse failed (exit " + rc2.to_string() + ")")
      @sys.exit(1)
    }

    // wasm-tools component embed
    let rc3 = run_shell_cmd(
      "wasm-tools component embed " +
      shell_quote(wit) +
      " --world " +
      shell_quote(world_arg) +
      " " +
      shell_quote(patched_wasm_path) +
      " -o " +
      shell_quote(embedded_path),
    )
    if rc3 != 0 {
      println(
        "Error: wasm-tools component embed failed (exit " +
        rc3.to_string() +
        ")",
      )
      @sys.exit(1)
    }

    // wasm-tools component new
    let rc4 = run_shell_cmd(
      "wasm-tools component new " +
      shell_quote(embedded_path) +
      " -o " +
      shell_quote(output),
    )
    if rc4 != 0 {
      println(
        "Error: wasm-tools component new failed (exit " + rc4.to_string() + ")",
      )
      @sys.exit(1)
    }

    // Cleanup temp files
    let _ = run_shell_cmd(
      "rm -f " +
      shell_quote(wat_path) +
      " " +
      shell_quote(patched_wat_path) +
      " " +
      shell_quote(patched_wasm_path) +
      " " +
      shell_quote(embedded_path),
    )
  } else {
    // No retptr imports - direct embed + new
    let embedded_path = tmp_prefix + "-embedded.wasm"

    let rc = run_shell_cmd(
      "wasm-tools component embed " +
      shell_quote(wit) +
      " --world " +
      shell_quote(world_arg) +
      " " +
      shell_quote(input) +
      " -o " +
      shell_quote(embedded_path),
    )
    if rc != 0 {
      println(
        "Error: wasm-tools component embed failed (exit " + rc.to_string() + ")",
      )
      @sys.exit(1)
    }

    let rc2 = run_shell_cmd(
      "wasm-tools component new " +
      shell_quote(embedded_path) +
      " -o " +
      shell_quote(output),
    )
    if rc2 != 0 {
      println(
        "Error: wasm-tools component new failed (exit " + rc2.to_string() + ")",
      )
      @sys.exit(1)
    }

    let _ = run_shell_cmd("rm -f " + shell_quote(embedded_path))
  }

  println("Created component: " + output)
}

///|
fn componentize_usage() -> Unit {
  println(
    "Usage: moon-component componentize <core.wasm> --wit <wit-dir> [--world <name>] -o <output.wasm>",
  )
}

///|
/// Parse WAT type definitions: (type (;N;) (func (param ...) (result i32)))
/// Returns Map[type_index -> param_string]
fn parse_wat_types(wat : String) -> Map[Int, String] {
  let types : Map[Int, String] = {}
  let lines = split_lines(wat)
  for line in lines {
    let trimmed = trim_string(line)
    // Match: (type (;N;) (func ...))
    if not(trimmed.has_prefix("(type (;")) {
      continue
    }
    // Extract type index N from (type (;N;) ...)
    let after_prefix = substring_after(trimmed, "(type (;")
    guard after_prefix is Some(rest) else { continue }
    let semicolon_pos = string_index_of(rest, ";)")
    guard semicolon_pos is Some(pos) else { continue }
    let index_str = string_substring(rest, 0, pos)
    let index = parse_int(index_str)
    guard index is Some(idx) else { continue }
    // Extract params: everything in (func (...))
    // trimmed: (type (;N;) (func (param ...) (result i32)))
    // We need to strip the outer two closing parens: ")))"  -> remove last 2
    let func_start = string_index_of(trimmed, "(func ")
    guard func_start is Some(fs) else { continue }
    let func_body = string_substring(
      trimmed,
      fs + 6,
      trimmed.length() - 2, // remove trailing ))  (one for func, one for type)
    )
    // Remove (result i32) and extract just the params
    let params = extract_params_from_func(func_body)
    types[idx] = params
  }
  types
}

///|
/// Extract parameter portion from a func body string.
/// Input like: "(param i32 i32 i32 i32) (result i32)"
/// Output: "(param i32 i32 i32 i32)"
fn extract_params_from_func(func_body : String) -> String {
  let sb = StringBuilder::new()
  let mut depth = 0
  let chars = func_body.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '(' {
      // Check if this starts (result
      let rest = string_substring(func_body, i, func_body.length())
      if rest.has_prefix("(result ") {
        // Skip entire (result ...)
        depth = 1
        i = i + 1
        while i < chars.length() && depth > 0 {
          if chars[i] == '(' {
            depth = depth + 1
          } else if chars[i] == ')' {
            depth = depth - 1
          }
          i = i + 1
        }
        continue
      }
    }
    sb.write_char(chars[i])
    i = i + 1
  }
  trim_string(sb.to_string())
}

///|
/// Apply retptr patches to WAT text.
/// 1. Find import lines matching retptr_imports
/// 2. Replace their type reference with inlined params (no result)
/// 3. Remove drop after corresponding call instructions
fn patch_wat(
  wat : String,
  retptr_imports : Array[@codegen.RetptrImportInfo],
) -> String {
  let types = parse_wat_types(wat)
  let lines = split_lines(wat)

  // Build lookup set for retptr imports: "MODULE\tNAME" -> true
  let retptr_set : Map[String, Bool] = {}
  for info in retptr_imports {
    retptr_set[info.import_module + "\t" + info.func_name] = true
  }

  // First pass: find import lines, extract func indices to patch
  let func_indices_to_patch : Map[Int, Bool] = {}
  let patched_lines : Array[String] = []
  for line in lines {
    let trimmed = trim_string(line)
    if trimmed.has_prefix("(import ") {
      // Parse: (import "MODULE" "NAME" (func (;F;) (type T)))
      let parsed = parse_import_line(trimmed)
      match parsed {
        Some((module_name, func_name, func_index, type_index)) => {
          let key = module_name + "\t" + func_name
          if retptr_set.contains(key) {
            // This import needs patching
            func_indices_to_patch[func_index] = true
            // Replace with inlined params (no result, no type ref)
            let params = types.get(type_index).unwrap_or("")
            let new_line = "  (import \"" +
              module_name +
              "\" \"" +
              func_name +
              "\" (func (;" +
              func_index.to_string() +
              ";) " +
              params +
              "))"
            patched_lines.push(new_line)
            continue
          }
        }
        None => ()
      }
    }
    patched_lines.push(line)
  }

  // Second pass: remove drop after call N where N is a patched func
  let result_lines : Array[String] = []
  let mut skip_next = false
  for i, line in patched_lines {
    if skip_next {
      skip_next = false
      continue
    }
    let trimmed = trim_string(line)
    // Check if this line is "call N" where N is patched
    if trimmed.has_prefix("call ") {
      let idx_str = string_substring(trimmed, 5, trimmed.length())
      let idx = parse_int(idx_str)
      match idx {
        Some(n) =>
          if func_indices_to_patch.contains(n) {
            // Check if next line is "drop"
            if i + 1 < patched_lines.length() {
              let next_trimmed = trim_string(patched_lines[i + 1])
              if next_trimmed == "drop" {
                skip_next = true
              }
            }
          }
        None => ()
      }
    }
    result_lines.push(line)
  }
  result_lines.join("\n")
}

///|
/// Parse an import line like:
///   (import "module" "name" (func (;N;) (type M)))
/// Returns (module, name, func_index, type_index) or None
fn parse_import_line(line : String) -> (String, String, Int, Int)? {
  // Find first and second quoted strings
  let first_quote = find_quoted_string(line, 0)
  guard first_quote is Some((module_name, after1)) else { return None }
  let second_quote = find_quoted_string(line, after1)
  guard second_quote is Some((func_name, _after2)) else { return None }
  // Find func index: (func (;N;)
  let func_marker = string_index_of(line, "(func (;")
  guard func_marker is Some(fm) else { return None }
  let after_func = string_substring(line, fm + 8, line.length())
  let func_semi = string_index_of(after_func, ";)")
  guard func_semi is Some(fs) else { return None }
  let func_idx_str = string_substring(after_func, 0, fs)
  let func_idx = parse_int(func_idx_str)
  guard func_idx is Some(fi) else { return None }
  // Find type index: (type N)
  let type_marker = string_index_of(line, "(type ")
  guard type_marker is Some(tm) else { return None }
  let after_type = string_substring(line, tm + 6, line.length())
  let type_paren = string_index_of(after_type, ")")
  guard type_paren is Some(tp) else { return None }
  let type_idx_str = string_substring(after_type, 0, tp)
  let type_idx = parse_int(type_idx_str)
  guard type_idx is Some(ti) else { return None }
  Some((module_name, func_name, fi, ti))
}

///|
/// Find a double-quoted string starting at or after position `from`.
/// Returns (extracted_string, position_after_closing_quote)
fn find_quoted_string(s : String, from : Int) -> (String, Int)? {
  let chars = s.to_array()
  let mut i = from
  // Find opening quote
  while i < chars.length() && chars[i] != '"' {
    i = i + 1
  }
  if i >= chars.length() {
    return None
  }
  i = i + 1 // skip opening quote
  let sb = StringBuilder::new()
  while i < chars.length() && chars[i] != '"' {
    sb.write_char(chars[i])
    i = i + 1
  }
  if i >= chars.length() {
    return None
  }
  Some((sb.to_string(), i + 1))
}

// --- String utility helpers ---

///|
fn split_lines(s : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for ch in s {
    if ch == '\n' {
      result.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(ch)
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    result.push(last)
  }
  result
}

///|
fn trim_string(s : String) -> String {
  let chars = s.to_array()
  let mut start = 0
  while start < chars.length() && (chars[start] == ' ' || chars[start] == '\t') {
    start = start + 1
  }
  let mut end = chars.length()
  while end > start &&
        (
          chars[end - 1] == ' ' ||
          chars[end - 1] == '\t' ||
          chars[end - 1] == '\r'
        ) {
    end = end - 1
  }
  if start == 0 && end == chars.length() {
    return s
  }
  let sb = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
fn substring_after(s : String, prefix : String) -> String? {
  if s.has_prefix(prefix) {
    Some(string_substring(s, prefix.length(), s.length()))
  } else {
    None
  }
}

///|
fn string_index_of(s : String, needle : String) -> Int? {
  let s_chars = s.to_array()
  let n_chars = needle.to_array()
  if n_chars.length() == 0 {
    return Some(0)
  }
  if n_chars.length() > s_chars.length() {
    return None
  }
  for i = 0; i <= s_chars.length() - n_chars.length(); i = i + 1 {
    let mut found = true
    for j = 0; j < n_chars.length(); j = j + 1 {
      if s_chars[i + j] != n_chars[j] {
        found = false
        break
      }
    }
    if found {
      return Some(i)
    }
  }
  None
}

///|
fn string_substring(s : String, start : Int, end : Int) -> String {
  let chars = s.to_array()
  let sb = StringBuilder::new()
  let actual_end = if end > chars.length() { chars.length() } else { end }
  for i = start; i < actual_end; i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.to_string()
}

///|
fn parse_int(s : String) -> Int? {
  let trimmed = trim_string(s)
  if trimmed.length() == 0 {
    return None
  }
  let mut result = 0
  let mut negative = false
  let chars = trimmed.to_array()
  let mut i = 0
  if chars[0] == '-' {
    negative = true
    i = 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
    i = i + 1
  }
  Some(if negative { -result } else { result })
}
