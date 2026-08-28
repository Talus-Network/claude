#!/usr/bin/env bash
# Smoke-test runner for the __TOOL_NAME__ Nexus Tool.
#
# Usage:
#   ./test.sh start [--port N]   build and start the server; print examples
#   ./test.sh stop  [--port N]   stop the server
#   ./test.sh run   [--port N]   start, validate the tool, stop
#   ./test.sh dev   [--port N]   start and stream logs; Ctrl+C stops the server
#
# Note on POST /invoke: the toolkit encodes a successful response as canonical
# BCS (`OffchainToolOutput`), not JSON — piping it to `jq` produces garbage.
# Only /health and /meta return JSON. `run` therefore uses
# `nexus tool validate offchain`, which is the canonical local check.
set -euo pipefail

TOOL_NAME="__TOOL_NAME__"
TOOL_PATH="__TOOL_PATH__"
WORKSPACE_DIR="$(cd "$(dirname "$0")/__WORKSPACE_CARGO_DIR__" && pwd)"
SAMPLE_JSON='__SAMPLE_JSON__'
DEFAULT_PORT=8080

SUBCMD="${1:-}"
shift || true
PORT="$DEFAULT_PORT"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) PORT="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# The toolkit mounts /meta and /invoke under the tool's `path()`, so a tool
# with a non-empty path() serves them at <base>/<path>/… , not at the root.
# `nexus tool validate offchain` must be pointed at the path-scoped URL too.
BASE_URL="http://localhost:${PORT}"
if [[ -n "$TOOL_PATH" ]]; then
    TOOL_URL="${BASE_URL}/${TOOL_PATH}"
else
    TOOL_URL="$BASE_URL"
fi

RUNDIR="${TMPDIR:-/tmp}/${USER:-nobody}-${TOOL_NAME}-${PORT}"
PID_FILE="${RUNDIR}.pid"
LOG_FILE="${RUNDIR}.log"

# ── helpers ───────────────────────────────────────────────────────────────────

build() {
    echo "► Building $TOOL_NAME (first run may take a few minutes)..."
    if ! (cd "$WORKSPACE_DIR" && cargo +stable build --package "$TOOL_NAME") \
            >"$LOG_FILE" 2>&1; then
        echo "  Build failed. Last lines from $LOG_FILE:" >&2
        tail -20 "$LOG_FILE" >&2
        exit 1
    fi
    echo "  Build complete."
}

start_server() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Server already running (PID $(cat "$PID_FILE"))."
        return
    fi
    build
    local binary="$WORKSPACE_DIR/target/debug/$TOOL_NAME"
    if [[ ! -x "$binary" ]]; then
        echo "  Binary not found at $binary" >&2; exit 1
    fi
    echo "► Starting server on port $PORT..."
    BIND_ADDR="127.0.0.1:${PORT}" "$binary" >>"$LOG_FILE" 2>&1 &
    echo $! >"$PID_FILE"
    echo "► Waiting for /health..."
    for i in $(seq 1 50); do
        if curl -sf "${BASE_URL}/health" >/dev/null 2>&1; then
            echo "  Ready. PID: $(cat "$PID_FILE")  Logs: $LOG_FILE"; return
        fi
        if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "  Server exited prematurely. Last lines from $LOG_FILE:" >&2
            tail -20 "$LOG_FILE" >&2
            rm -f "$PID_FILE"; exit 1
        fi
        sleep 0.2
    done
    echo "  Timed out waiting for server. Last lines from $LOG_FILE:" >&2
    tail -20 "$LOG_FILE" >&2
    stop_server; exit 1
}

stop_server() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo "No PID file found — server may not be running."; return
    fi
    local pid; pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        echo "► Stopping server (PID $pid)..."
        kill "$pid"
    else
        echo "Process $pid not found — cleaning up PID file."
    fi
    rm -f "$PID_FILE"
}

print_examples() {
    echo ""
    echo "── examples ─────────────────────────────────────────────────────────────────"
    echo ""
    echo "  Validate (canonical check — health + meta + output-schema oneOf):"
    echo "    nexus tool validate offchain --url ${TOOL_URL}"
    echo ""
    echo "  Health (JSON):"
    echo "    curl -s ${BASE_URL}/health"
    echo ""
    echo "  Meta (JSON — fqn, timeout, input/output schemas):"
    echo "    curl -s ${TOOL_URL}/meta | jq ."
    echo ""
    echo "  Invoke — the response body is BCS, not JSON. Write it to a file:"
    echo "    curl -s -X POST ${TOOL_URL}/invoke \\"
    echo "      -H 'Content-Type: application/json' \\"
    printf "      -d '%s' \\\\\n" "$SAMPLE_JSON"
    echo "      --output invoke.bcs"
    echo ""
    echo "    A JSON body instead of BCS means the toolkit rejected the request;"
    echo "    it carries an \"error\" field explaining why."
    echo ""
    echo "  Tool metadata for registration (no server needed):"
    echo "    ${WORKSPACE_DIR}/target/debug/${TOOL_NAME} --meta | jq ."
    echo ""
    echo "─────────────────────────────────────────────────────────────────────────────"
    echo ""
}

# Canonical smoke test. Prefers `nexus tool validate offchain`, which checks
# GET /health, GET /meta, and that the output schema has the required
# top-level oneOf. Falls back to raw /health + /meta when the CLI is absent.
validate_tool() {
    if command -v nexus >/dev/null 2>&1; then
        echo "► nexus tool validate offchain --url ${TOOL_URL}"
        nexus tool validate offchain --url "$TOOL_URL"
        return
    fi

    echo "► nexus CLI not on PATH — falling back to health and meta"
    echo "  GET ${BASE_URL}/health"
    curl -sf "${BASE_URL}/health" >/dev/null || { echo "  health failed" >&2; return 1; }
    echo "  ok"
    echo "  GET ${TOOL_URL}/meta"
    local meta
    meta=$(curl -sf "${TOOL_URL}/meta") || { echo "  meta failed" >&2; return 1; }
    if command -v jq >/dev/null 2>&1; then
        echo "$meta" | jq .
    else
        echo "$meta"
    fi
}

dev_mode() {
    start_server
    print_examples
    local server_pid
    server_pid=$(cat "$PID_FILE")
    echo "► Streaming logs (Ctrl+C to stop server)..."
    # Prefer GNU tail --pid (exits automatically when the server process dies).
    # gtail = GNU tail via Homebrew on macOS; plain tail on Linux is usually GNU.
    local tail_bin=""
    if command -v gtail >/dev/null 2>&1; then
        tail_bin="gtail"
    elif tail --help 2>/dev/null | grep -q -- '--pid'; then
        tail_bin="tail"
    fi
    if [[ -n "$tail_bin" ]]; then
        trap 'stop_server; exit 0' INT TERM
        "$tail_bin" -f --pid="$server_pid" "$LOG_FILE"
    else
        # BSD tail (macOS without gtail): background tail + poll loop
        tail -f "$LOG_FILE" &
        local tail_pid=$!
        trap 'kill "$tail_pid" 2>/dev/null; stop_server; exit 0' INT TERM
        while kill -0 "$server_pid" 2>/dev/null; do
            sleep 0.5
        done
        kill "$tail_pid" 2>/dev/null
    fi
    echo "  Server stopped."
    stop_server
}

# ── dispatch ──────────────────────────────────────────────────────────────────

case "$SUBCMD" in
    start) start_server; print_examples ;;
    stop)  stop_server ;;
    run)   start_server; validate_tool; stop_server ;;
    dev)   dev_mode ;;
    *)     echo "Usage: $0 {start|stop|run|dev} [--port N]" >&2; exit 1 ;;
esac
