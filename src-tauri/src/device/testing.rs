//! Test doubles shared by the device tests.

use std::sync::Mutex;
use std::time::Duration;

use super::runner::{CommandResult, CommandRunner};

type Handler = Box<dyn Fn(&str, &[&str]) -> CommandResult + Send + Sync>;

/// Scripted stand-in for the shell: records every call and answers from `handler`.
pub struct FakeRunner {
    handler: Handler,
    calls: Mutex<Vec<Vec<String>>>,
    detached: Mutex<Vec<Vec<String>>>,
    pub launch_succeeds: bool,
}

impl FakeRunner {
    pub fn new(handler: impl Fn(&str, &[&str]) -> CommandResult + Send + Sync + 'static) -> Self {
        Self { handler: Box::new(handler), calls: Mutex::default(), detached: Mutex::default(), launch_succeeds: true }
    }

    /// Answers every call with an empty success.
    pub fn silent() -> Self {
        Self::new(|_, _| CommandResult::new("", 0))
    }

    pub fn calls(&self) -> Vec<Vec<String>> {
        self.calls.lock().unwrap().clone()
    }

    pub fn detached_launches(&self) -> Vec<Vec<String>> {
        self.detached.lock().unwrap().clone()
    }
}

fn record(executable: &str, args: &[&str]) -> Vec<String> {
    std::iter::once(executable).chain(args.iter().copied()).map(String::from).collect()
}

impl CommandRunner for FakeRunner {
    fn run(&self, executable: &str, args: &[&str], _timeout: Duration) -> CommandResult {
        self.calls.lock().unwrap().push(record(executable, args));
        (self.handler)(executable, args)
    }

    fn launch_detached(&self, executable: &str, args: &[&str]) -> bool {
        self.detached.lock().unwrap().push(record(executable, args));
        self.launch_succeeds
    }
}

pub fn strings(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| s.to_string()).collect()
}

/// Shaped like `adb devices -l` with daemon noise, a running and an offline emulator, and a phone.
pub const ADB_DEVICES: &str = "* daemon not running; starting now at tcp:5037\n\
* daemon started successfully\n\
List of devices attached\n\
emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1\n\
emulator-5556          offline\n\
R58M12345XY            device usb:1-1 product:beyond1 model:SM_G973F device:beyond1 transport_id:3\n";
