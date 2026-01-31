wit_bindgen::generate!({
    world: "types-test",
    path: "wit/world.wit",
});

struct Component;

export!(Component);

impl exports::local::types_test::primitives::Guest for Component {
    fn echo_s32(val: i32) -> i32 {
        val
    }

    fn echo_s64(val: i64) -> i64 {
        val
    }

    fn echo_f32(val: f32) -> f32 {
        val
    }

    fn echo_f64(val: f64) -> f64 {
        val
    }

    fn echo_bool(val: bool) -> bool {
        val
    }

    fn echo_string(val: String) -> String {
        val
    }
}

impl exports::local::types_test::enums::Guest for Component {
    fn echo_color(c: exports::local::types_test::enums::Color) -> exports::local::types_test::enums::Color {
        c
    }

    fn color_name(c: exports::local::types_test::enums::Color) -> String {
        use exports::local::types_test::enums::Color;
        match c {
            Color::Red => "red".to_string(),
            Color::Green => "green".to_string(),
            Color::Blue => "blue".to_string(),
        }
    }
}

impl exports::local::types_test::flags_test::Guest for Component {
    fn echo_permissions(p: exports::local::types_test::flags_test::Permissions) -> exports::local::types_test::flags_test::Permissions {
        p
    }

    fn has_read(p: exports::local::types_test::flags_test::Permissions) -> bool {
        p.contains(exports::local::types_test::flags_test::Permissions::READ)
    }

    fn has_write(p: exports::local::types_test::flags_test::Permissions) -> bool {
        p.contains(exports::local::types_test::flags_test::Permissions::WRITE)
    }
}

impl exports::local::types_test::containers::Guest for Component {
    fn sum_list(vals: Vec<i32>) -> i32 {
        vals.iter().sum()
    }

    fn echo_list_s64(vals: Vec<i64>) -> Vec<i64> {
        vals
    }

    fn count_list(vals: Vec<String>) -> i32 {
        vals.len() as i32
    }

    fn divide(a: i32, b: i32) -> Result<i32, String> {
        if b == 0 {
            Err("division by zero".to_string())
        } else {
            Ok(a / b)
        }
    }
}

impl exports::local::types_test::multi_params::Guest for Component {
    fn add2(a: i32, b: i32) -> i32 {
        a + b
    }

    fn add3(a: i32, b: i32, c: i32) -> i32 {
        a + b + c
    }

    fn add4(a: i32, b: i32, c: i32, d: i32) -> i32 {
        a + b + c + d
    }

    fn concat3(a: String, b: String, c: String) -> String {
        format!("{}{}{}", a, b, c)
    }

    fn mixed_params(n: i32, s: String, b: bool) -> String {
        format!("{}:{}:{}", n, s, b)
    }
}

impl exports::local::types_test::side_effects::Guest for Component {
    fn no_return(_msg: String) {
        // Side effect only
    }

    fn no_params_no_return() {
        // No params, no return
    }
}
