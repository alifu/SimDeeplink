//! Clicking the tray icon while the popup is open first takes focus from the popup (which hides it) and then
//! delivers the click. Without a guard that click would show the popup again at once.

use std::time::{Duration, Instant};

const REOPEN_GRACE: Duration = Duration::from_millis(300);

#[cfg_attr(target_os = "macos", allow(dead_code))]
#[derive(Debug, Default)]
pub struct ToggleGuard {
    hidden_at: Option<Instant>,
}

#[cfg_attr(target_os = "macos", allow(dead_code))]
impl ToggleGuard {
    pub fn note_hidden(&mut self, now: Instant) {
        self.hidden_at = Some(now);
    }

    /// Whether a tray click at `now` should open the popup, given that it is currently hidden.
    pub fn should_show(&self, now: Instant) -> bool {
        self.hidden_at.is_none_or(|hidden| now.saturating_duration_since(hidden) > REOPEN_GRACE)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shows_when_the_popup_was_never_hidden() {
        assert!(ToggleGuard::default().should_show(Instant::now()));
    }

    #[test]
    fn ignores_the_click_that_only_closed_the_popup() {
        let mut guard = ToggleGuard::default();
        let hidden = Instant::now();
        guard.note_hidden(hidden);

        assert!(!guard.should_show(hidden + Duration::from_millis(50)));
    }

    #[test]
    fn shows_again_on_a_later_click() {
        let mut guard = ToggleGuard::default();
        let hidden = Instant::now();
        guard.note_hidden(hidden);

        assert!(guard.should_show(hidden + Duration::from_secs(2)));
    }
}
