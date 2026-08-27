#![doc = include_str!("../README.md")]

use nexus_toolkit::bootstrap;

mod __TOOL_NAME_SNAKE__;

#[tokio::main]
async fn main() {
    // Initialise the logger before validate_config so its log::error! calls
    // are visible. bootstrap! also calls try_init() internally; the second
    // call is a no-op.
    let _ = nexus_toolkit::env_logger::try_init();

    // bootstrap! intercepts `--meta`, prints the tool metadata as JSON, and
    // exits without serving. CI runs that against the built image to extract
    // registration data, where the runtime secrets are not injected — so
    // config validation must not run on that path, or `--meta` exits 1 with
    // "required env var ... is not set" and registration cannot proceed.
    if !std::env::args().any(|arg| arg == "--meta") {
        __TOOL_NAME_SNAKE__::validate_config();
    }

    bootstrap!([__TOOL_NAME_SNAKE__::__TOOL_NAME_PASCAL__])
}
