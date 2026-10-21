/// True for a single URL with a scheme, including custom app schemes such as `myapp://path?id=1`.
/// Same rule as the Swift app's `String.isLink`.
pub fn is_link(text: &str) -> bool {
    if text.chars().any(char::is_whitespace) {
        return false;
    }
    let Some((scheme, rest)) = text.split_once(':') else { return false };
    let mut chars = scheme.chars();
    let valid_scheme = chars.next().is_some_and(|c| c.is_ascii_alphabetic())
        && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '.' | '-'));
    // Something must follow "scheme:" and the optional "//".
    valid_scheme && !rest.strip_prefix("//").unwrap_or(rest).is_empty()
}

#[cfg(test)]
mod tests {
    use super::is_link;

    #[test]
    fn accepts_web_and_custom_scheme_links() {
        for link in ["https://example.com/a?b=1&c=2", "myapp://path?id=1", "tel:+62812", "a+b.c-d://x"] {
            assert!(is_link(link), "{link}");
        }
    }

    #[test]
    fn rejects_text_that_is_not_a_single_link() {
        for text in ["", "example.com", "https://", "myapp:", "my app://x", "https://a b", "1app://x", "-d://x", "://x"] {
            assert!(!is_link(text), "{text}");
        }
    }
}
