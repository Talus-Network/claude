# talus-plugins

A Claude Code plugin marketplace for working with [Talus](https://talus.network) and [Nexus](https://github.com/Talus-Network/nexus-sdk).

Plugins live under [`plugins/`](plugins/). The marketplace manifest is at [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).

## Plugins

### [`talus`](plugins/talus/)

Helpers for building Nexus Tools and Talus-related artifacts. Tracks Nexus `v2.0.0-rc.final`.

- **`/talus:tool-new [--auto] [tool-name] [fqn-prefix] [description]`** — Scaffold an **off-chain** [Nexus Tool](https://github.com/Talus-Network/nexus-tools) — an HTTP service in Rust implementing the `NexusTool` trait — and walk the user through implementing it. Detects whether the current directory is a nexus-tools-style workspace (root `Cargo.toml` with `members = ["tools/*"]`) and adds a workspace member at `tools/<tool-name>/`, generating the extra files that repo's CI requires (`tools.json`, `build.rs`, `[[bin]]`, version-threaded FQN, toolkit-config integration test), or otherwise scaffolds a fresh standalone crate. Reference templates are read from the latest upstream `Talus-Network/nexus-tools` at invocation time, or from the local clone if you are inside one — no frozen baked-in templates. Pass `--auto` to skip all confirmation gates and infer missing arguments.

- **`/talus:tool-new-onchain [--auto] [tool-name] [fqn-prefix] [description]`** — Scaffold an **on-chain** Nexus Tool: a Sui Move package whose `public fun execute` a workflow calls inside a PTB. Use it when the tool must mutate on-chain state, move assets, or be verifiable and atomic. Places the package at `onchain/<tool-name>/` inside a nexus-tools checkout, or standalone otherwise; resolves the `nexus_primitives` / `nexus_interface` dependencies from a local nexus checkout, a vendored `deps/` tree, or a pinned git revision. Verifies with `sui move build` and `sui move test`, then walks `sui client publish`, `nexus tool register onchain`, and `nexus tool validate onchain`.

## Install

In any Claude Code session (CLI or VS Code extension):

```text
/plugin marketplace add Talus-Network/claude
/plugin install talus@talus-plugins
```

To use a local checkout instead:

```text
/plugin marketplace add /path/to/this/repo
/plugin install talus@talus-plugins
```

## Try a single plugin without installing (CLI only)

```sh
claude --plugin-dir /path/to/this/repo/plugins/talus
```

Then in the session:

```text
/talus:tool-new weather-current xyz.example.weather "Fetches current weather conditions"
/talus:tool-new-onchain counter-tool xyz.example.counter "Increments an on-chain counter"
```

All arguments are optional; the skill prompts for whatever is missing. Add `--auto` to skip prompts entirely:

```text
/talus:tool-new --auto "Fetches current weather conditions"
```

## Status

Early. One plugin, two skills — off-chain (Rust) and on-chain (Move) tool scaffolding. More to come.
