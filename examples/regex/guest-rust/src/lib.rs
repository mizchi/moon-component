wit_bindgen::generate!({
    world: "regex-app",
    path: "wit/world.wit",
});

struct Component;

export!(Component);

impl exports::local::regex::regex::Guest for Component {
    fn is_match(pattern: String, text: String) -> bool {
        let re = match regex::Regex::new(&pattern) {
            Ok(re) => re,
            Err(_) => return false,
        };
        re.is_match(&text)
    }

    fn replace(pattern: String, text: String, replacement: String) -> String {
        let re = match regex::Regex::new(&pattern) {
            Ok(re) => re,
            Err(_) => return text,
        };
        re.replace_all(&text, replacement).to_string()
    }
}
