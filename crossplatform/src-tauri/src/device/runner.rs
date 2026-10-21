use std::io::Read;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(30);
const POLL_INTERVAL: Duration = Duration::from_millis(10);
const DRAIN_GRACE: Duration = Duration::from_secs(1);
/// A runaway tool must not fill memory; the reader keeps draining the pipe but stops storing.
const MAX_OUTPUT_BYTES: usize = 1024 * 1024;

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
#[cfg(windows)]
const DETACHED_PROCESS: u32 = 0x0000_0008;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandResult {
    pub output: String,
    pub exit_code: i32,
}

impl CommandResult {
    pub fn new(output: impl Into<String>, exit_code: i32) -> Self {
        Self { output: output.into(), exit_code }
    }

    pub fn failure(message: impl Into<String>) -> Self {
        Self::new(message, -1)
    }

    pub fn succeeded(&self) -> bool {
        self.exit_code == 0
    }

    pub fn trimmed_output(&self) -> &str {
        self.output.trim()
    }
}

/// Runs external tools without a shell, so arguments are never re-interpreted.
pub trait CommandRunner: Send + Sync {
    fn run(&self, executable: &str, args: &[&str], timeout: Duration) -> CommandResult;

    /// Starts a long-lived process (such as the Android emulator) and does not wait for it.
    fn launch_detached(&self, executable: &str, args: &[&str]) -> bool;

    fn run_default(&self, executable: &str, args: &[&str]) -> CommandResult {
        self.run(executable, args, DEFAULT_TIMEOUT)
    }
}

#[derive(Debug, Default, Clone, Copy)]
pub struct ProcessRunner;

impl CommandRunner for ProcessRunner {
    fn run(&self, executable: &str, args: &[&str], timeout: Duration) -> CommandResult {
        let (reader, writer) = match os_pipe::pipe().and_then(|(r, w)| w.try_clone().map(|w2| (r, w, w2))) {
            Ok((reader, out, err)) => (reader, (out, err)),
            Err(e) => return CommandResult::failure(format!("Error: {e}")),
        };

        let mut command = Command::new(executable);
        command.args(args).stdin(Stdio::null()).stdout(writer.0).stderr(writer.1);
        hide_console_window(&mut command);

        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(e) => return CommandResult::failure(format!("Error: {e}")),
        };
        // The parent must not keep a copy of the write end, or the reader would never see end-of-file.
        drop(command);

        // Do not wait for end-of-file on the pipe: a daemon that the tool starts (such as the adb server)
        // inherits it and would keep the read open long after the tool itself has finished.
        let buffer = Arc::new(Mutex::new(Vec::new()));
        let reached_end = spawn_reader(reader, Arc::clone(&buffer));

        let deadline = Instant::now() + timeout;
        let mut timed_out = false;
        let status = loop {
            match child.try_wait() {
                Ok(Some(status)) => break Some(status),
                Ok(None) if Instant::now() >= deadline => {
                    timed_out = true;
                    let _ = child.kill();
                    break child.wait().ok();
                }
                Ok(None) => thread::sleep(POLL_INTERVAL),
                Err(_) => break None,
            }
        };

        // Normally end-of-file arrives at once; if a leftover child holds the pipe, stop waiting.
        let _ = reached_end.recv_timeout(DRAIN_GRACE);

        let output = String::from_utf8_lossy(&buffer.lock().unwrap_or_else(|e| e.into_inner())).into_owned();
        if timed_out {
            return CommandResult::new(format!("{output}\nTimed out after {}s", timeout.as_secs()), -1);
        }
        CommandResult::new(output, status.and_then(|s| s.code()).unwrap_or(-1))
    }

    fn launch_detached(&self, executable: &str, args: &[&str]) -> bool {
        let mut command = Command::new(executable);
        command.args(args).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
        detach(&mut command);
        match command.spawn() {
            Ok(mut child) => {
                // Reap the process when it ends, or it stays a zombie until the app quits.
                thread::spawn(move || {
                    let _ = child.wait();
                });
                true
            }
            Err(_) => false,
        }
    }
}

fn spawn_reader(mut reader: os_pipe::PipeReader, buffer: Arc<Mutex<Vec<u8>>>) -> mpsc::Receiver<()> {
    let (done, reached_end) = mpsc::channel();
    thread::spawn(move || {
        let mut chunk = [0u8; 4096];
        loop {
            match reader.read(&mut chunk) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    let mut stored = buffer.lock().unwrap_or_else(|e| e.into_inner());
                    let room = MAX_OUTPUT_BYTES.saturating_sub(stored.len()).min(n);
                    stored.extend_from_slice(&chunk[..room]);
                }
            }
        }
        let _ = done.send(());
    });
    reached_end
}

/// A GUI app has no console; without this flag every `adb` call would flash a terminal window on Windows.
#[cfg(windows)]
fn hide_console_window(command: &mut Command) {
    use std::os::windows::process::CommandExt;
    command.creation_flags(CREATE_NO_WINDOW);
}

#[cfg(not(windows))]
fn hide_console_window(_command: &mut Command) {}

#[cfg(windows)]
fn detach(command: &mut Command) {
    use std::os::windows::process::CommandExt;
    command.creation_flags(CREATE_NO_WINDOW | DETACHED_PROCESS);
}

/// Its own process group: Ctrl-C or a hang-up in the terminal that started the app must not stop the emulator.
#[cfg(unix)]
fn detach(command: &mut Command) {
    use std::os::unix::process::CommandExt;
    command.process_group(0);
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The platform's own shell, so the same tests run on every CI machine.
    fn script(unix: &str, windows: &str) -> (&'static str, Vec<String>) {
        if cfg!(windows) {
            ("cmd", vec!["/C".into(), windows.into()])
        } else {
            ("sh", vec!["-c".into(), unix.into()])
        }
    }

    fn run_script(unix: &str, windows: &str, timeout: Duration) -> CommandResult {
        let (exe, args) = script(unix, windows);
        let args: Vec<&str> = args.iter().map(String::as_str).collect();
        ProcessRunner.run(exe, &args, timeout)
    }

    #[test]
    fn captures_output_and_exit_code() {
        let result = run_script("echo hello world", "echo hello world", DEFAULT_TIMEOUT);

        assert!(result.succeeded());
        assert_eq!(result.trimmed_output(), "hello world");
    }

    #[test]
    fn merges_stderr_into_the_output() {
        let result = run_script("echo out; echo err 1>&2", "echo out& echo err 1>&2", DEFAULT_TIMEOUT);

        assert!(result.output.contains("out"));
        assert!(result.output.contains("err"));
    }

    #[test]
    fn reports_a_non_zero_exit_code() {
        let result = run_script("exit 3", "exit 3", DEFAULT_TIMEOUT);

        assert!(!result.succeeded());
        assert_eq!(result.exit_code, 3);
    }

    #[test]
    fn fails_cleanly_when_the_executable_does_not_exist() {
        let result = ProcessRunner.run_default("definitely-not-here-simdeeplink", &[]);

        assert!(!result.succeeded());
        assert!(result.output.starts_with("Error:"), "{}", result.output);
    }

    #[test]
    fn stops_a_command_that_runs_past_the_timeout() {
        let started = Instant::now();

        let result = run_script("sleep 10", "ping -n 11 127.0.0.1 >nul", Duration::from_millis(300));

        assert!(!result.succeeded());
        assert!(result.output.contains("Timed out"));
        assert!(started.elapsed() < Duration::from_secs(5));
    }

    #[test]
    fn detached_launch_reports_whether_the_process_started() {
        let (exe, args) = script("exit 0", "exit 0");
        let args: Vec<&str> = args.iter().map(String::as_str).collect();

        assert!(ProcessRunner.launch_detached(exe, &args));
        assert!(!ProcessRunner.launch_detached("definitely-not-here-simdeeplink", &[]));
    }

    #[cfg(unix)]
    #[test]
    fn does_not_interpret_shell_syntax_in_arguments() {
        let result = ProcessRunner.run_default("echo", &["$(whoami);ls", "a&b"]);

        assert_eq!(result.trimmed_output(), "$(whoami);ls a&b");
    }

    #[cfg(unix)]
    #[test]
    fn reads_output_larger_than_the_pipe_buffer_without_hanging() {
        let result = ProcessRunner.run("yes", &["x"], Duration::from_secs(1));

        assert!(result.output.len() > 10_000);
        assert!(result.output.len() <= MAX_OUTPUT_BYTES + 64, "plus the timeout note");
    }

    #[cfg(unix)]
    #[test]
    fn does_not_wait_for_a_child_that_keeps_the_pipe_open_after_the_tool_exits() {
        let started = Instant::now();

        let result = ProcessRunner.run("sh", &["-c", "echo started; (sleep 5 &) ; exit 0"], Duration::from_secs(10));

        assert!(result.succeeded());
        assert_eq!(result.trimmed_output(), "started");
        assert!(started.elapsed() < Duration::from_secs(4));
    }

    #[cfg(unix)]
    #[test]
    fn a_crash_is_not_reported_as_a_timeout() {
        let result = ProcessRunner.run("sh", &["-c", "kill -SEGV $$"], Duration::from_secs(5));

        assert!(!result.succeeded());
        assert!(!result.output.contains("Timed out"));
    }
}
