//! `__FQN_PREFIX__.__TOOL_NAME_FQN_TAIL__@1`
//!
//! __DESCRIPTION__

use {
    nexus_sdk::{fqn, ToolFqn},
    nexus_toolkit::*,
    schemars::JsonSchema,
    serde::{Deserialize, Serialize},
    std::sync::OnceLock,
};

// ── config ────────────────────────────────────────────────────────────────────
//
// All required env vars are READ AT STARTUP by validate_config() and cached
// in module-level OnceLock<String> statics. Accessors return the cached value
// (no further env reads). Process aborts at startup if any var is missing —
// fail-fast over silent runtime failures.
//
// To add a new required env var:
//   1. Declare `static <NAME>: OnceLock<String> = OnceLock::new();`
//   2. Add `<NAME>.set(load_required("<NAME>")).expect("validate_config called twice");`
//      to validate_config()
//   3. Add an accessor function returning &'static str

static EXAMPLE_API_KEY: OnceLock<String> = OnceLock::new();

/// Reads and caches all required env vars. Called from main() before bootstrap!.
/// Assumes env_logger is already initialised.
pub(crate) fn validate_config() {
    EXAMPLE_API_KEY
        .set(load_required("EXAMPLE_API_KEY"))
        .expect("validate_config called twice");
    // TODO: add one `<STATIC>.set(load_required("<VAR>")).expect(...);` line per secret
}

/// Reads a required env var or aborts the process. Logs the name (never the value).
fn load_required(name: &str) -> String {
    match std::env::var(name) {
        Ok(v) => {
            log::debug!(target: "__TOOL_NAME_SNAKE__", "env var {name} loaded");
            v
        }
        Err(_) => {
            log::error!(target: "__TOOL_NAME_SNAKE__", "fatal: required env var {name} is not set");
            std::process::exit(1);
        }
    }
}

#[allow(dead_code)] // used by invoke() once real logic is wired
fn example_api_key() -> &'static str {
    EXAMPLE_API_KEY
        .get()
        .expect("validate_config must run before any accessor")
}

// ── types ─────────────────────────────────────────────────────────────────────

#[derive(Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub(crate) struct Input {
    // TODO: replace with real input fields
    pub(crate) placeholder: String,
}

// TODO: replace Ok's fields with real output ports; add domain-specific error
// variants for distinct failure modes (e.g. err_not_found, err_rate_limited,
// err_invalid_input) so DAG edges can route on specific failure types.
//
// The toolkit encodes /invoke responses as canonical BCS `OffchainToolOutput`
// by first serialising this enum to JSON. That encoder requires:
//   * an externally tagged enum (the serde default — do NOT add
//     #[serde(tag = ...)], untagged, or a flatten attribute),
//   * exactly one variant per response,
//   * each variant's payload to be a JSON *object*.
// So every variant must be a STRUCT variant. A unit variant (`Ok`) or a tuple
// variant (`Ok(String)`) compiles fine but fails at runtime with
// `output_serialization_error`. An empty success variant is written `Ok {}`.
// A port whose value is an array is carried as a `many` NexusData value.
#[derive(Serialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
// Scaffold-only: invoke() returns just ErrUpstream so far. Delete this
// attribute once every variant is reachable. Keep it at the enum level —
// putting it on an individual variant makes rustfmt expand every variant
// onto multiple lines, which fails `cargo fmt --check` against the
// nexus-tools rustfmt config.
#[allow(dead_code)]
pub(crate) enum Output {
    Ok { result: String },
    ErrUpstream { reason: String },
    ErrConfig { reason: String },
}

pub(crate) struct __TOOL_NAME_PASCAL__;

// ── impl ──────────────────────────────────────────────────────────────────────

impl NexusTool for __TOOL_NAME_PASCAL__ {
    type Input = Input;
    type Output = Output;

    async fn new() -> Self {
        Self
    }

    fn fqn() -> ToolFqn {
        // Generic workspace / standalone:
        fqn!("__FQN_PREFIX__.__TOOL_NAME_FQN_TAIL__@1")
        // nexus-tools mode — delete the two lines above and uncomment these
        // four (already wrapped the way rustfmt wants them):
        // fqn!(concat!(
        //     "__FQN_PREFIX__.__TOOL_NAME_FQN_TAIL__@",
        //     env!("TOOL_FQN_VERSION")
        // ))
    }

    fn path() -> &'static str {
        "/__TOOL_NAME_FQN_TAIL__" // explicitly overrides the trait default ("")
    }

    fn description() -> &'static str {
        "__DESCRIPTION__"
    }

    // The trait's `timeout()` defaults to 10 seconds and is published in
    // /meta, so it becomes the Tool's registered on-chain timeout. Every
    // external call in invoke() must use a client timeout SMALLER than this
    // value. If the upstream genuinely needs longer, override it here instead
    // of raising the client timeout past the declared one:
    //
    // fn timeout() -> std::time::Duration {
    //     std::time::Duration::from_secs(30)
    // }

    // Optional admission policy, applied after signed HTTP has authenticated
    // the caller. Default is allow; returning Err yields a signed 403.
    // AuthContext carries the verified invoker identity.
    //
    // async fn authorize(&self, ctx: AuthContext) -> AnyResult<()> {
    //     if ctx.invoker_id != "0x1111" {
    //         anyhow::bail!("leader not allowed");
    //     }
    //     Ok(())
    // }

    async fn health(&self) -> AnyResult<StatusCode> {
        // TODO: probe every service this tool depends on.
        // Return Err(...) if any dependency is unhealthy — leader nodes use
        // this endpoint to decide whether to route invocations.
        Ok(StatusCode::OK)
    }

    async fn invoke(&self, input: Self::Input) -> Self::Output {
        let Input { placeholder } = input;
        log::debug!(target: "__TOOL_NAME_SNAKE__", "invoke called: placeholder={:?}", placeholder);

        // TODO: access secrets via the module-level accessors (e.g.
        // example_api_key()). Never call std::env::var() directly here —
        // that defeats the fail-fast guarantee from validate_config and
        // re-reads the env on every request.
        //
        // TODO: set an explicit timeout on every external call; a slow upstream
        // will hold this invocation open indefinitely otherwise. Keep it below
        // the value `timeout()` returns (10s by default) so the tool can still
        // map the failure to an Err variant before the runtime gives up.
        //
        // TODO: implement real logic; return the appropriate Output variant.
        // Do NOT call example_api_key() until you also arrange for
        // validate_config to run in your tests (or refactor the call site).
        Output::ErrUpstream {
            reason: format!("not implemented yet (placeholder={placeholder:?})"),
        }
    }
}

// ── tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// Verifies the unimplemented scaffold returns ErrUpstream; catches
    /// regressions if the variant name or return type changes.
    #[tokio::test]
    async fn invoke_returns_err_upstream() {
        let tool = __TOOL_NAME_PASCAL__::new().await;
        let input = Input {
            placeholder: "test".to_string(),
        };
        let output = tool.invoke(input).await;
        assert!(matches!(output, Output::ErrUpstream { .. }));
    }

    /// Verifies health() returns 200 OK on the unimplemented scaffold;
    /// catches regressions before real dependency checks are wired.
    #[tokio::test]
    async fn health_returns_ok() {
        let tool = __TOOL_NAME_PASCAL__::new().await;
        let status = tool.health().await.unwrap();
        assert_eq!(status, StatusCode::OK);
    }
}
