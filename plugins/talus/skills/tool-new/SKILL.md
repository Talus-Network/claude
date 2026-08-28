---
name: tool-new
description: Scaffold a new **off-chain** Nexus Tool in Rust (an HTTP service implementing the NexusTool trait) and implement it end-to-end based on the user's description. Detects context: inside the Talus-Network/nexus-tools repo (or a fork) adds a member at offchain/tools/<name>/ and generates the extra files the CI pipeline requires (tools.json, build.rs, [[bin]], version-threaded FQN); in any other Cargo workspace with members = ["tools/*"] adds a member at tools/<name>/; otherwise scaffolds a standalone crate. Fetches the latest reference patterns from upstream Talus-Network/nexus-tools at invocation time (or reads them locally when inside a clone or fork) — no baked-in templates; the NexusTool trait signatures are taken from upstream math/src/i64/add.rs at every invocation. After the scaffold compiles, replaces the placeholder Input/Output and invoke() logic with the real implementation — for well-known APIs (OpenAI, Anthropic, etc.) it applies the actual request/response shapes directly rather than asking the user to design the schema. Use when the user asks to "create a Nexus Tool", "scaffold a Nexus Tool", "build a new Nexus Tool", "new Talus tool", or similar. For a Move tool that runs on Sui and mutates on-chain state, use the `tool-new-onchain` skill instead.
argument-hint: "[--auto] [tool-name] [fqn-prefix] [description]"
allowed-tools: Bash(pwd) Bash(command -v *) Bash(head *) Bash(find *) Bash(chmod +x *) Bash(bash -n *) Bash(grep *) Bash(sed -n *) Bash(gh api *)
---

# `tool-new` — scaffold a new Nexus Tool in Rust

An off-chain Nexus Tool is an HTTPS service that implements the `NexusTool` trait from the `nexus-toolkit` crate. The canonical code reference is [Talus-Network/nexus-tools](https://github.com/Talus-Network/nexus-tools).

The authoritative development guidelines live in [Talus-Network/nexus-docs](https://github.com/Talus-Network/nexus-docs) — the SDK repo's own `docs/` tree was removed and moved there:

| Topic | Page |
|---|---|
| Building an off-chain tool, end to end | [guides/tool-development/build-offchain-tool.md](https://github.com/Talus-Network/nexus-docs/blob/main/guides/tool-development/build-offchain-tool.md) |
| `NexusTool` trait and toolkit runtime | [reference/toolkit/rust.md](https://github.com/Talus-Network/nexus-docs/blob/main/reference/toolkit/rust.md) |
| Signed HTTP, TLS, proxy requirements | [guides/tool-development/tool-communication.md](https://github.com/Talus-Network/nexus-docs/blob/main/guides/tool-development/tool-communication.md) |
| Result verification and key rotation | [guides/tool-development/verify-offchain-tool-result.md](https://github.com/Talus-Network/nexus-docs/blob/main/guides/tool-development/verify-offchain-tool-result.md) |
| `nexus tool` CLI surface | [reference/cli/tool.md](https://github.com/Talus-Network/nexus-docs/blob/main/reference/cli/tool.md) |

Do not link to `nexus-sdk/blob/main/docs/...` anywhere — those paths 404.

This skill scaffolds a working skeleton, then implements the real Input/Output and invoke() logic based on the user's description. The `NexusTool` trait signatures used in the generated code come from upstream `tools/math/src/i64/add.rs` (fetched at every invocation) — never from a baked-in copy of the trait.

## Arguments

Supported invocation forms:

```
/talus:tool-new my-tool xyz.acme.weather "Fetches current weather"
/talus:tool-new --auto "Fetches current weather"
/talus:tool-new --auto Fetches current weather
/talus:tool-new "Fetches current weather" --auto
/talus:tool-new Fetches current weather --auto
```

**Parsing rules.** Strip `--auto` or `--yes` wherever it appears — its presence sets auto mode (see below). From the remaining tokens:

- A token matching the reverse-domain pattern (contains dots, e.g. `xyz.acme.weather`) → `fqn_prefix`
- **Without `--auto`:** the first remaining token matching `^[a-z][a-z0-9-]*$` → `tool_name` (single-word names like `calculator` are valid here).
- **With `--auto`:** only a token matching `^[a-z][a-z0-9]*(-[a-z0-9]+)+$` (hyphenated, e.g. `current-weather`) → `tool_name`. Single lowercase words are treated as description to avoid misidentifying prose words (e.g. "fetches" in "Fetches weather data") as the tool name.
- Everything else, joined → `description`

**Named arguments:**

- `tool_name` — kebab-case crate/dir name (e.g. `weather-open-meteo-forecast`). When omitted, auto mode composes it from the workspace's directory naming convention plus the source and action it derives from the description. The "Convention inference" step in Phase 2 owns the rules; the outcome reflects whatever shape existing tools in the workspace already use (single-segment names for a flat workspace, multi-segment hyphenated names for a `domain.category.source.action` workspace, etc.). Without auto mode, ask.
- `fqn_prefix` — reverse-domain namespace prefix **without trailing dot** (e.g. `xyz.taluslabs.weather.open-meteo`). When omitted, auto mode composes `<workspace_root>[.<category>][.<source>]` — workspace root from convention inference, category and source extracted from the description. **Without auto mode, never invent or default this — always ask.** The final FQN is `<fqn_prefix>.<action>@1` where `action` is the leaf segment (the canonical endpoint name for well-known APIs, or a verb+object derived from the description otherwise) cast to the kebab/snake case that the workspace already uses.
- `description` — one-line description of what the tool does. Required in all modes; ask if missing even in auto mode.

**Auto mode** (`--auto` / `--yes`) **or all three arguments provided**: skip every confirmation gate throughout all phases — placement, FQN preview, overwrite check. Infer anything not explicitly provided using the rules above.

## Context (computed at invocation)

- Working directory: !`pwd`

Only `pwd` runs as a pre-injection — every other detection is done in Phase 1 below, because the alternatives ("does X exist?") need to handle the not-present case without aborting the pre-processor on a non-zero exit. The Bash patterns the procedure uses are pre-authorized via the `allowed-tools` frontmatter, so they won't trigger permission prompts.

## Procedure

### Phase 1 — Detect context and confirm placement

Run these checks via the Bash tool (each is in the skill's allowed-tools allowlist — no permission prompt):

1. `command -v cargo` — empty stdout means `cargo` is not on PATH. Warn the user; the scaffold can still be written, but Phase 6 verification won't run.
2. `command -v gh` — empty stdout means we'll fall back to WebFetch in Phase 3 instead of `gh api`.
3. `command -v just` — empty stdout means `just tools::check` can't be used later (use `cargo +stable check` directly).
4. `find . -maxdepth 1 -name Cargo.toml -type f` — non-empty: a `Cargo.toml` is present at the current directory root.
5. `find . -maxdepth 2 -path ./offchain/Cargo.toml -type f` — non-empty: a `Cargo.toml` exists one level down at `offchain/`. This is the Rust workspace root when working from the nexus-tools repo root.
6. If step 4 was non-empty, `head -n 50 Cargo.toml` — look for `members = ["tools/*"]`.
7. If step 5 was non-empty, `head -n 50 offchain/Cargo.toml` — look for `members = ["tools/*"]`.
8. If step 5 was non-empty, `find . -maxdepth 2 -path ./offchain/tools -type d` — non-empty: the `offchain/tools/` directory exists. Combined with step 7 containing `members = ["tools/*"]`, this confirms a nexus-tools-style workspace at the repo root.
9. If step 4 was non-empty and step 6 contains `members = ["tools/*"]`, `find . -maxdepth 2 -path ./tools -type d` — confirms the `tools/` directory exists (working from inside `offchain/`).

Decide placement and mode from the results:

- **Step 7 contains `members = ["tools/*"]` AND step 8 non-empty (nexus-tools, working from repo root):** The Rust workspace is at `offchain/`; place the new tool at `offchain/tools/$tool_name/`. All `cargo` commands in later phases must be run from `offchain/`. The `tools/.just` file is at `offchain/tools/.just`. This is **nexus-tools mode** — apply the additional CI requirements in Phase 4.5. Prefer reading templates locally (Phase 3, step 1 — Local read) over fetching from upstream.
- **Step 6 contains `members = ["tools/*"]` AND step 9 non-empty (nexus-tools, working from inside `offchain/`):** Place the new tool at `tools/$tool_name/`. Run `cargo` commands from the current directory. The `tools/.just` file is at `tools/.just`. This is **nexus-tools mode** — apply Phase 4.5. Prefer reading templates locally.
- **Step 4 non-empty AND step 6 contains `members = ["tools/*"]` AND steps 7–9 empty:** Generic workspace (not nexus-tools, but same layout). Place at `tools/$tool_name/`. Standard scaffold, no Phase 4.5 extras.
- **Step 4 non-empty AND step 6 does NOT contain `members = ["tools/*"]`:** Unrelated Cargo project. In auto mode, default to standalone. Otherwise ask the user: (a) treat as standalone (tool goes in a subdirectory), or (b) abort.
- **Step 5 non-empty AND step 7 does NOT contain `members = ["tools/*"]`:** `offchain/Cargo.toml` exists but is not a tools workspace. Fall through: check step 4; if that also fails, use standalone mode. In auto mode, proceed with standalone. Otherwise ask the user to confirm before proceeding.
- **Steps 4, 5 both empty:** Standalone mode. Default to `$tool_name/` under the current directory.

In auto mode, skip the placement confirmation — proceed with the detected mode without asking. Never overwrite an existing target directory without explicit user confirmation (this check is not bypassed by auto mode).

### Phase 2 — Collect inputs

> **AUTO MODE (`--auto` / `--yes`) or all three arguments provided:** Do NOT ask any questions in this phase. Apply the rules below silently, print a one-line summary of what was resolved (workspace root prefix, category, source, action, directory name), and proceed immediately to Phase 3. The user said they do not want to be asked.

#### Convention inference

Auto-mode resolution combines two independent signals:

- **Workspace inference** (workspace mode only, when ≥ 1 existing tool crate is found) — anchors the FQN root and the directory naming rule to whatever the workspace already does.
- **Description-driven composition** — extracts category, source, and action from the user's description. **Always runs in auto mode**, regardless of whether existing tools are present. A brand-new repo with no other tools still gets a "clever" FQN like `com.example.weather.open-meteo.forecast` if the description supports it.

The two sources are layered: workspace inference fixes what it can; description-driven composition fills in everything else. Neither blocks the other.

**Workspace inference** (skip this whole sub-section for empty workspaces and standalone mode):

1. List existing tool crate directories. From the tools root (`offchain/tools` from repo root, `tools` from inside `offchain/`):
   `find <tools_root> -mindepth 2 -maxdepth 2 -name Cargo.toml | xargs -n1 dirname`
2. For each directory, collect every `fqn!()` call in its `src/` tree:
   `grep -rEh 'fqn!\(' <dir>/src/`
   Extract the FQN string literal — works for both `fqn!("…@1")` and `fqn!(concat!("…@", env!("TOOL_FQN_VERSION")))` (the literal segment is what matters; everything before `@`).
3. Tabulate (directory name) ↔ (list of FQNs inside).
4. Infer the **workspace root prefix**: the longest `.`-separated prefix shared by **every** existing FQN. For taluslabs's nexus-tools this is `xyz.taluslabs`.
5. For each directory, classify the crate type and record the directory naming rule:
   - **Single-tool crate** (exactly one FQN): typically `dir_name == "-".join(fqn_tail.split("."))` where `fqn_tail` is the FQN minus the workspace root. Example: `llm-openai-chat-completion/` ↔ `xyz.taluslabs.llm.openai.chat-completion` (tail `llm.openai.chat-completion` → dir `llm-openai-chat-completion`). ✅
   - **Multi-tool crate** (multiple FQNs sharing a common prefix): typically `dir_name == "-".join(shared_prefix.split("."))` where `shared_prefix` is the longest `.`-separated prefix common to every FQN in the directory, minus the workspace root. Example: `social-twitter/` ↔ {`xyz.taluslabs.social.twitter.post-tweet`, `xyz.taluslabs.social.twitter.like-tweet`, …} → shared `social.twitter` → dir `social-twitter`.
6. Record for later steps:
   - **Workspace root prefix** (e.g. `xyz.taluslabs`)
   - **Directory naming rule** in effect (single-tool full-tail mirroring is the default; multi-tool shared-prefix is supplemental)
   - **List of known multi-tool crates** as `(dir_name, shared_fqn_prefix)` pairs
   - **Typical FQN depth past the root** — the modal count of `.`-separated segments after the workspace root across single-tool crates. For taluslabs's nexus-tools this is 3 (`category.source.action`). **Informational only**; the rules in Phase 2 do not gate any output on this value. It is used solely by the depth-gap warning below to flag descriptions that look under-specified relative to the workspace convention.

**Defaults when workspace inference is skipped or empty:**

- Workspace root prefix → `com.example` (auto mode prints a warning: "update before publishing").
- Directory naming rule → single-tool full-tail mirroring (dir name = FQN tail past the root joined with `-`).
- Multi-tool crate list → empty.
- Typical FQN depth → unknown (no warning fires).

These defaults are what makes the rest of Phase 2 robust to a brand-new repo. They never block description-driven composition.

Use the rest of Phase 2 to resolve the new tool's inputs.

#### Resolve each value

- **`description`** — one-line description; used in both `Cargo.toml` `[package].description` and `impl NexusTool::description`. Ask if missing in both interactive and auto mode — there is no reasonable default. **Validate: must not contain `"` (double quote) or `\` (backslash).** The description is substituted unescaped into a Rust string literal (`fn description() -> &'static str { "..." }`) and a TOML string (`[package].description = "..."`) — either character breaks the generated file. If the user-provided description contains one, ask them to rephrase (e.g. replace `Says "hello"` with `Says hello (with quotes)`); in auto mode print the rejection reason and stop rather than silently mangling.

- **`fqn_prefix`** — reverse-domain prefix that goes **before** the action segment. No trailing dot. Beyond the workspace root, the prefix may carry zero or more middle segments (category, source) extracted from the description.
  - **Validate against the protocol's FQN grammar, not just a loose shape.** The parser behind `fqn!` splits the whole FQN on `.` and requires: at least three parts, and **every** part matching `^[a-z][a-z0-9_-]+$` — lowercase, **at least two characters**, never starting with a digit, `-`, or `_`. So each segment of `fqn_prefix` must be ≥ 2 characters, and so must the action segment. A single-letter segment (`x.acme.foo`) is rejected at compile time by `fqn!`, not at registration. Source: [build-offchain-tool.md](https://github.com/Talus-Network/nexus-docs/blob/main/guides/tool-development/build-offchain-tool.md).
  - If the description yields a one-character category, source, or action, expand it to a real word rather than emitting it (e.g. `x` → drop the segment; action `go` is fine, action `t` is not).
  - *Interactive:* if not provided, suggest the workspace root prefix from convention inference and let the user extend it (e.g. `xyz.taluslabs.weather.open-meteo`). **Never invent or default this without asking.**
  - *Auto mode:* if the user provided an explicit `fqn_prefix` argument, honor it as-is — skip the rest of this bullet. Otherwise compose `fqn_prefix = <root> [. <category>] [. <source>]` where the middle segments are description-driven and optional:
    1. **Workspace root** — from workspace inference if available, else the default `com.example`.
    2. **Category** (optional middle segment) — a noun naming the tool's domain, drawn from the description. Include only when the description has a clear domain noun. Examples: "Fetches current weather" → `weather`; "Posts a tweet" → `social`; "Stores data in Redis" → `storage`. Omit when the description is purely operational with no clear domain noun (e.g. "Adds two integers" → no category).
    3. **Source** (optional middle segment) — the data source / service the tool wraps. Include only when the description names a service. Kebab-case the service name. Examples: `OpenAI` → `openai`, `Open-Meteo` → `open-meteo`, `Twitter` → `twitter`. Omit for pure-computation tools (math, encoding, pure transformation) and for tools that don't wrap a specific external service.
  - **Robustness note:** category and source extraction never depends on workspace inference. A brand-new repo with no existing tools still produces `com.example.weather.open-meteo.forecast` from a description like "Fetches current weather from Open-Meteo" — only the root differs from a nexus-tools invocation.

- **Action segment (auto mode)** — the leaf segment of the FQN; the verb-phrase or noun that names what the tool does. This becomes `tool_name_fqn_tail` (the case-style is applied per the case-inference rule below).
  - *For well-known services / APIs:* **prefer the canonical endpoint or method name from the API itself** over guessing from the description prose. Apply your knowledge of the named service. Examples:
    - Open-Meteo `GET /forecast` → `forecast`
    - OpenAI `POST /v1/chat/completions` → `chat-completion`
    - Anthropic `POST /v1/messages` → `messages`
    - Twitter `POST /2/tweets` → `post-tweet`; `GET /2/tweets/:id` → `get-tweet`; `POST /2/users/:id/likes` → `like-tweet`
    - Stripe `POST /v1/charges` → `create-charge`
  - *For pure-computation tools or unknown APIs:* derive the action from the description's verb + object, dropping fillers ("Calculate squared distance" → `squared-distance`; "Send a notification" → `send-notification`; "Add two integers" → `add`). When the verb is ambiguous, prefer the most specific noun in the description.

- **`tool_name`** — kebab-case crate name (= directory name). Validate: `^[a-z][a-z0-9-]*$`. Derive `tool_name_snake` = hyphens → underscores; `tool_name_pascal` = PascalCase of the snake form.
  - *Interactive:* if not provided, suggest a value based on the directory naming rule (default below) applied to the resolved FQN, and let the user override.
  - *Auto mode:* if the user provided an explicit `tool_name` argument, honor it. Otherwise apply the directory naming rule:
    `tool_name = "-".join(fqn_prefix.segments_past_workspace_root + [action])`
    - Segments past the root come from whatever `fqn_prefix` ended up being (description-driven middle segments included or omitted as resolved above).
    - With segments: prefix `com.example.weather.open-meteo`, root `com.example`, action `forecast` → `tool_name = weather-open-meteo-forecast`.
    - Without segments (description had no category and no service): prefix `com.example`, root `com.example`, action `add` → `tool_name = add`.
  - **Workspace inference does not gate this rule** — the same formula applies in a brand-new repo (where the root is the `com.example` default), in a workspace whose existing tools happen to be flat, and in nexus-tools (where the root is `xyz.taluslabs`). Workspace inference only changes the **root** and surfaces the multi-tool-crate warning below.

- **Multi-tool crate detection.** After composing `tool_name` and the full FQN, check the recorded list of known multi-tool crates from convention inference. If the assembled FQN matches one of those `shared_fqn_prefix` values (i.e. the new tool's prefix-up-to-the-leaf equals an existing multi-tool crate's shared prefix), surface this to the user before generating:
  > An existing `<dir>/` crate already covers `<shared_fqn_prefix>.*` with N tools. Adding the new tool to that crate is a different operation (modify `src/`, extend `bootstrap!([…])`, etc.). This skill currently generates a new sibling crate only.
  - *Auto mode:* print the warning, default to creating a new sibling crate, proceed. Do not silently modify the existing multi-tool crate.
  - *Interactive mode:* ask whether to create the new sibling (proceed) or abort (and let the user add to the existing crate manually).

- **Depth-gap warning (workspace mode only, when typical FQN depth is known).** After composing the FQN, count the segments past the workspace root in the assembled value (i.e. `fqn_prefix.segments_past_root` count + 1 for the action). Compare to the typical FQN depth recorded in convention inference:
  - **Equal or greater:** no warning.
  - **One less than typical** (e.g. workspace uses `category.source.action` = 3 segments but our FQN is `category.action` = 2): the description most likely didn't name a service. Print:
    > Note: existing tools in this workspace use `<typical>`-segment FQN tails (e.g. one concrete example from inference, like `social.twitter.post-tweet`). The composed FQN `<our-fqn>` has `<ours>` segments past the root — the description didn't name a source service, so the source segment was omitted. To get a richer FQN that matches the workspace convention, re-run with a description that names the service (e.g. "Fetches current weather from Open-Meteo" instead of "Fetches current weather").
  - **Two or more less:** print the same warning but reference both gaps. This is rare in practice — the description is probably too sparse for auto mode to do a useful job.
  - The warning is **informational only** — auto mode proceeds with the composed FQN. Interactive mode shows it before the FQN preview confirmation so the user can re-run with a richer description if they want.

- **`tool_name_fqn_tail`** — the case-style-adjusted form of the action segment (single segment — multi-segment FQN structure is carried by `fqn_prefix`, not by the tail). Inferred — never asked.
  - *Both modes:* scan existing tool source files for `fqn!(` calls (e.g. `grep -rEhn 'fqn!\(' . --include='*.rs'`) and inspect each FQN-tail segment (between the last `.` and the `@`). If **any existing tail contains `_`**, the project has an explicit snake_case convention → set `tool_name_fqn_tail = action.replace("-", "_")`. Otherwise (any existing tail contains `-`, or all tails are single-word, or there are no existing tools at all) → kebab-case → set `tool_name_fqn_tail = action` (unchanged). Print the resolved tail.
  - **Rationale.** Kebab-case is the default in all modes — it matches URL/API conventions (`/post-tweet`, `/chat-completion`), aligns with the `action` value derived from real API endpoints in the previous bullet, and matches upstream nexus-tools. Snake_case is only chosen when the workspace already shows an explicit underscore convention worth preserving. A brand-new repo therefore gets kebab by default, not snake — that's robust and ergonomic.

- **FQN preview** — show the computed final FQN (`<fqn_prefix>.<tool_name_fqn_tail>@1`) and the derived directory name (`tool_name`).
  - *Interactive:* ask the user to confirm before proceeding. In nexus-tools mode note that the literal `@1` is the local-development default; CI threads the real version via `build.rs`.
  - *Auto mode:* print it and proceed immediately.

### Phase 3 — Fetch reference templates

The canonical reference files live under `offchain/` in the nexus-tools repo. Adjust local read paths depending on working depth (repo root vs. inside `offchain/`).

Files to read (two groups — note the difference):

- **Repo-root files** (path is the same regardless of working depth):
  - `README.md` — contains the "Adding a new tool" section; read in full
- **`offchain/`-rooted files** (use `offchain/<path>` from repo root; strip `offchain/` when already inside `offchain/`):
  - `offchain/Cargo.toml` (workspace root)
  - `offchain/rust-toolchain.toml`
  - `offchain/tools/.just`
  - `offchain/tools/math/Cargo.toml`
  - `offchain/tools/math/build.rs`
  - `offchain/tools/math/tools.json`
  - `offchain/tools/math/src/main.rs`
  - `offchain/tools/math/src/i64/add.rs`
  - `offchain/tools/math/README.md`
  - `offchain/tools/math/tests/toolkit_config_v2.rs` — the toolkit-runtime-config integration test the CI pipeline expects each tool to carry (see Phase 4.5)

In order of preference:

1. **Local read** if nexus-tools mode was detected. Read using the paths above (adjusted for working depth).

2. **`gh` fetch** if `gh` is on PATH. Use each path as listed above (repo-root files without prefix, `offchain/`-rooted files with `offchain/` prefix):
   `gh api repos/Talus-Network/nexus-tools/contents/<path> -H "Accept: application/vnd.github.raw"`

3. **WebFetch fallback** if neither: fetch `https://raw.githubusercontent.com/Talus-Network/nexus-tools/main/<path>` for each.

If none of these can produce the templates (offline, no clone, no `gh`, no WebFetch), stop and tell the user the skill needs network access or a local clone to proceed. Never fabricate templates.

### Phase 4 — Generate files

Use the Write tool for new files (not Edit). The `Cargo.toml` is generated inline based on upstream patterns read in Phase 3; the three source files (`main.rs`, `<tool_name_snake>.rs`, `README.md`) come from templates in this skill's own repo, fetched and substituted as described below.

#### `<target-dir>/Cargo.toml`

- **Workspace member mode (nexus-tools or generic):** use `*.workspace = true` for every inherited field (edition, version, repository, homepage, license, readme, authors, keywords, categories) — same shape as upstream `tools/math/Cargo.toml`. Dependencies use `*.workspace = true` for `schemars`, `serde`, `tokio`, `nexus-toolkit`, `nexus-sdk`, **`log`** (the template uses `log::*` macros directly, so `log` must be a direct dep — `nexus_toolkit::*` does not re-export the `log` macros).
  - **nexus-tools mode only:** also add `[build-dependencies]` with `serde_json.workspace = true` and `toml = "0.8"` — required by `build.rs`, which parses both `tools.json` and `Cargo.toml` at compile time. For `[[bin]]` and the FQN version threading, see Phase 4.5.
- **Standalone mode:** use explicit values from the upstream workspace `[workspace.package]` and `[workspace.dependencies]` sections. Pin `nexus-sdk` and `nexus-toolkit` to the same `git` + `tag` upstream uses (read these from the fetched workspace `Cargo.toml`, never hardcode). Include `log = "0.4"` (or the version pinned by the upstream workspace) as a direct dep — required by the template's `log::*` macros.

#### `<target-dir>/src/main.rs`, `<target-dir>/src/<tool_name_snake>.rs`, `<target-dir>/README.md`

These three files come from templates that are co-located with this skill's installation. The skill's base directory is provided in the execution context — look for `Base directory for this skill:` in your active context. Read each template locally using the Read tool:

| Template | Target path |
|---|---|
| `<SKILL_BASE_DIR>/templates/main.rs` | `<target-dir>/src/main.rs` |
| `<SKILL_BASE_DIR>/templates/tool.rs` | `<target-dir>/src/<tool_name_snake>.rs` |
| `<SKILL_BASE_DIR>/templates/README.md` | `<target-dir>/README.md` |

The templates live on disk next to this skill — no network call is needed or correct. If the base directory is not visible in the context, fall back in order: `gh api repos/Talus-Network/claude/contents/plugins/talus/skills/tool-new/templates/<file> -H "Accept: application/vnd.github.raw"`, then WebFetch at `https://raw.githubusercontent.com/Talus-Network/claude/main/plugins/talus/skills/tool-new/templates/<file>`.

Each template contains `__PLACEHOLDER__` markers. Substitute every marker before writing:

| Placeholder | Value |
|---|---|
| `__TOOL_NAME_SNAKE__` | `tool_name` with hyphens → underscores (Rust module name, log target) |
| `__TOOL_NAME_PASCAL__` | PascalCase of `__TOOL_NAME_SNAKE__` (struct name) |
| `__TOOL_NAME_FQN_TAIL__` | `tool_name_fqn_tail` from Phase 2 — the **leaf action segment** of the FQN, cast to the workspace's case convention (kebab `forecast`, `post-tweet`, `chat-completion` or snake `forecast`, `post_tweet`). Multi-segment FQN structure (category, source) lives in `__FQN_PREFIX__`. Used in the FQN tail and the HTTP `path()`. |
| `__FQN_PREFIX__` | `fqn_prefix` from Phase 2 |
| `__DESCRIPTION__` | `description` from Phase 2 |
| `__COMPUTED_FQN__` | `<fqn_prefix>.<tool_name_fqn_tail>@1` |

After writing each file, confirm no markers remain. If any are present, the substitution missed something — fix before continuing:

```
grep -l '__[A-Z_]*__' <target-dir>/src/main.rs <target-dir>/src/<tool_name_snake>.rs <target-dir>/README.md
```

Empty output = success.

**Verify trait signatures against upstream (mandatory).**

The template carries a working `impl NexusTool for ...` block, but the `NexusTool` trait can evolve in upstream. After substitution, compare every method signature in the generated `src/<tool_name_snake>.rs`'s `impl NexusTool` block against the same methods in the math reference tool fetched in Phase 3 (`offchain/tools/math/src/i64/add.rs`). For each method (`new`, `fqn`, `path`, `description`, `health`, `invoke`):

- The argument list, receiver (`self`, `&self`, none), return type, and `async`-ness must match math/add.rs exactly.
- If our template's signature differs from upstream, **upstream wins** — update the generated file to match. The template may lag.

This means math/add.rs is the source of truth for trait method shapes at every invocation, not anything baked into this skill.

**Mode-specific edits after substitution:**

- **nexus-tools mode:** in `src/<tool_name_snake>.rs`, switch the `fqn!()` form. The template's `fn fqn()` body carries the active `fqn!("...@1")` call under a `// Generic workspace / standalone:` comment, followed by a commented-out four-line `// fqn!(concat!(...))` block. Delete the comment and the active call, then uncomment the block, leaving only the `fqn!(concat!(...))` call. The commented block is already wrapped the way rustfmt wants it — do not re-join it onto one line, or `cargo fmt --check` fails. The version is then threaded from `build.rs` (see Phase 4.5).
- **No secrets needed:** if analysis of the tool description finds no plausible required env var, empty the body of `validate_config` and delete the `EXAMPLE_API_KEY` static, the `example_api_key()` accessor, and `load_required` (if nothing else calls it). Do not delete `validate_config` itself — `main.rs` calls it unconditionally.
- **Additional secrets:** to add more env vars, declare another `static <NAME>: OnceLock<String>` and accessor, and add another `.set(load_required("<NAME>"))` line to `validate_config`. Follow the EXAMPLE_API_KEY pattern exactly.

### Phase 4.5 — nexus-tools additional files (nexus-tools mode only)

Skip this phase entirely in generic workspace mode and standalone mode.

**Copy every generated file's shape from the reference tool (`offchain/tools/math/`), and read the README fetched in Phase 3 for the surrounding process.** The two sources are not interchangeable, and where they disagree the reference tool wins:

> The README's "Adding a new tool" section currently shows a `tools.json` example containing only `environment`, `resources`, and `signed_http` — it **omits `command`**. `build.rs` panics at compile time when `tools.json["command"]` is absent, and every real tool in the repo (`math`, `http`, `llm-openai-chat-completion`, `templating-jinja`, `exchanges-coinbase`) uses `{"tool_name", "command", "environment"}`. Generating the README's shape produces a crate that does not build. This is a known upstream documentation drift — mention it to the user, then copy the real file.

Procedure:

1. In the README fetched in Phase 3, locate the section whose heading is "Adding a new tool" (or the closest equivalent if the heading has changed). It is the authority on **process** — CI triggers, discovery globs, deploy tracks, extra steps this skill does not know about.
2. **If the section is not found:** don't stop. Generate the files below from the reference tool, then tell the user the README section is missing so they can check [https://github.com/Talus-Network/nexus-tools](https://github.com/Talus-Network/nexus-tools) for process changes.
3. **If the section prescribes a step this list does not cover, follow it** — it is newer than this skill. Flag the discrepancy to the user.

Files to generate, each copied from `offchain/tools/math/` and adapted:

- **`tools.json`** at the crate root, shape `{"tool_name": "<crate>", "command": "<crate>", "environment": {"RUST_LOG": "info"}}`. `"command"` must equal the `[[bin]]` name and the crate name — `build.rs` asserts this. If the tool reads runtime secrets, add one `"environment"` entry per env var name; values are injected by the deployment pipeline, never hardcoded here.
- **`build.rs`** copied verbatim; do not invent it. It reads `tools.json["command"]`, asserts it matches the `[[bin]]` name in `Cargo.toml`, and emits `TOOL_FQN_VERSION` as a Cargo env var from the Docker build arg (defaulting to `"1"` locally). It requires `[build-dependencies]` with `serde_json` and `toml` — already added to `Cargo.toml` in Phase 4.
- **`[[bin]]`** in `Cargo.toml` with `name` equal to the crate name.
- **`fqn!()`** using `concat!("...", env!("TOOL_FQN_VERSION"))` so the content version flows from the CI build arg.
- **`tests/toolkit_config_v2.rs`**, adapted from the reference tool's copy. The CI `prepare` step generates a strict Toolkit runtime config (version 2) and mounts it as the per-tool `toolkit-config` secret; `register` validates it before publishing. This test is what proves the binary actually accepts that config: it spawns `env!("CARGO_BIN_EXE_<crate>")` with `NEXUS_TOOLKIT_CONFIG_PATH` pointing at a temp file containing `{"signed_http":{"mode":"disabled"}}` and `BIND_ADDR` on a free loopback port, then waits for the process to accept a TCP connection.

  Adapting it takes four changes, and the last one is not optional:
  1. `CARGO_BIN_EXE_math` → `CARGO_BIN_EXE_<crate>` (the crate name, hyphens included).
  2. The temp-directory prefix and the panic messages, so a failure names this tool.
  3. The test function name — `math_binary_accepts_workbench_toolkit_config` → `tool_binary_accepts_workbench_toolkit_config`.
  4. **One `.env("<VAR>", "test")` call on the `Command` per env var the tool's `validate_config` loads.** The reference tool has no required env vars; the scaffold ships with `EXAMPLE_API_KEY`, and `validate_config` calls `std::process::exit(1)` when a required var is missing. Without this the test fails with *"binary exited before accepting the Workbench Toolkit config"* and `fatal: required env var … is not set` on stderr — which reads like a toolkit-config problem but is not. Revisit this list in Phase 7 step 3 when the real env vars replace `EXAMPLE_API_KEY`.

### Phase 5 — Wire into workspace `tools/.just` (workspace mode only)

If the target is a workspace member, edit `tools/.just` (at `offchain/tools/.just` when working from the repo root, or `tools/.just` when working from inside `offchain/`) and append the new package name to each of these recipes, preserving existing ordering and indentation:

- `build` → `cargo +stable build --package <tool_name> --release`
- `check` → `cargo +stable check --package <tool_name>`
- `test` → `cargo +stable test --package <tool_name>`
- `fmt-check` → `cargo +"$nightly" fmt --package <tool_name> --check`
- `clippy` → `cargo +stable clippy --package <tool_name>`

The workspace root `Cargo.toml` does not need editing — `members = ["tools/*"]` discovers the new member automatically.

**Do not treat `.just` as the workspace's tool inventory.** Upstream's copy lists only a subset of the crates that actually exist under `offchain/tools/` (at the time of writing: `math` and `llm-openai-chat-completion`, out of a dozen). Convention inference in Phase 2 must enumerate tool directories with `find`, never by reading `.just`. Appending the new package to the recipes is still correct — the recipes are the developer entry point — but a package missing from them is normal, not a signal.

### Phase 6 — Verify the scaffold compiles

- **nexus-tools mode, working from repo root:** `cd offchain && cargo +stable check --package <tool_name>` (or `just tools::check` from `offchain/` if `just` is on PATH)
- **nexus-tools mode, working from `offchain/`:** `cargo +stable check --package <tool_name>` (or `just tools::check`)
- **Generic workspace:** `cargo +stable check --package <tool_name>`
- **Standalone:** `cargo check`

If it fails, diagnose and fix before proceeding. Common failure modes:

- `nexus-sdk` / `nexus-toolkit` versions don't match what upstream's workspace pins → re-read the workspace `Cargo.toml` and adjust.
- `env!("TOOL_FQN_VERSION")` not found (nexus-tools mode) → `build.rs` is missing or was not copied correctly.
- `[[bin]]` name mismatch (nexus-tools mode) → the `build.rs` assertion fires; ensure `[[bin]] name` equals `[package] name`.
- `tool_name` contains characters Cargo rejects → re-prompt for a valid name.
- Pre-existing directory at the target path → never overwrite without confirmation.

Before cross-referencing the checklist, scan the generated `Input` struct for secret-sounding field names. The grep is scoped to the `Input` struct only, so the OnceLock statics and accessor functions outside it (which legitimately contain `key`, `secret`, etc.) don't show up as false positives. Uses ERE (`-E`) for portable alternation across GNU and BSD grep:

```
sed -n '/struct Input/,/^}/p' src/<tool_name_snake>.rs \
  | grep -iE 'key|token|secret|password|credential|private|auth'
```

If anything matches, that field violates the secrets-via-env rule. Fix it with the OnceLock+accessor pattern (NOT direct `std::env::var` in `invoke`):

1. Remove the field from `Input`.
2. Add `static <NAME>: OnceLock<String> = OnceLock::new();` to the config section.
3. Add `<NAME>.set(load_required("<NAME>")).expect("validate_config called twice");` to `validate_config()`.
4. Add a private accessor: `fn <name>() -> &'static str { <NAME>.get().expect("validate_config must run before any accessor") }`.
5. Replace any reference to the old Input field with a call to the accessor in `invoke`.
6. Rerun `cargo check`.

`new()` takes no arguments (per the trait); it cannot read per-request secrets. All env vars are read once at startup by `validate_config`.

Cross-reference the generated files against [checklist.md](checklist.md) before declaring the scaffold done.

### Phase 7 — Implement

**This phase REPLACES the scaffold's placeholders with REAL WORKING CODE.** The scaffold from Phase 4 is a starting point, not the deliverable. By the end of this phase the tool must actually do what the user's description says: the `placeholder` field is gone, the real Input/Output shapes exist, `invoke()` makes the real call (or operates on the real inputs), and every `TODO` from the Phase 4 templates has been resolved. **Generating only the scaffold and stopping here is incomplete work** — return to this phase if any TODO remains.

> **Mode:**
> - **Auto mode (`--auto` / `--yes`) or all three positional args were provided:** implement everything below without asking. The user already gave you the description; further questions are friction.
> - **Interactive mode:** briefly state the plan (one paragraph naming the Input fields, Output variants, secrets, and HTTP client you intend to use), then implement. Do NOT ask the user to design the schema or decide field names — those follow from the description. Ask only if a piece of information is genuinely unavailable (an obscure private API with no documentation, for example).

Use the user's description plus your knowledge of the named service. **For well-known APIs and services (OpenAI, Anthropic, Slack, Stripe, GitHub, Postgres, Redis, S3, etc.) the request/response shapes, auth pattern, and endpoints are part of your training — apply them directly. Do not produce `placeholder: String` for an OpenAI tool; produce the real `model`, `messages`/`prompt`, `temperature`, `max_tokens` fields and the real `completion`, `usage`, `finish_reason` output shape.** Apply [build-offchain-tool.md](https://github.com/Talus-Network/nexus-docs/blob/main/guides/tool-development/build-offchain-tool.md) conventions throughout.

**Steps (perform in order, all of them, no skipping):**

1. **Replace the Input struct.** Delete the `placeholder` field entirely. Add the real input fields. snake_case names; descriptive (`model`, not `m`); separate ports for things the DAG should default independently (`prompt` and `context` as two ports, not one); be generic where the API allows. **Never add a secret as an Input field** — secrets are runtime config, not request input. The on-chain visibility rule is categorical even when an existing tool in the codebase violates it.

2. **Replace the Output enum.** Replace the placeholder `Ok { result: String }` with the actual success shape (e.g. for OpenAI completion: `Ok { completion: String, model: String, prompt_tokens: u32, completion_tokens: u32, finish_reason: String }`). Replace the generic `ErrUpstream`/`ErrConfig` with specific failure variants matching the real failure modes (`err_rate_limited`, `err_invalid_input`, `err_upstream`, `err_timeout`, `err_auth`, etc.). Output ports are flat — no nested response objects. Crucial ports must NOT be `Option<...>`; missing data surfaces as an `err_*` variant.

   **Encoder constraints — these fail at runtime, not at compile time.** The toolkit no longer returns the output as JSON. It serialises the enum to JSON, then re-encodes it as canonical BCS `OffchainToolOutput` (`encode_tagged_output` in `toolkit-rust/src/runtime.rs`). That encoder requires:
   - **Externally tagged.** The serde default. Never add `#[serde(tag = "...")]`, `#[serde(untagged)]`, or `#[serde(flatten)]` on the Output enum or its variants — the encoder rejects anything that does not serialise to a single-key object.
   - **Every variant is a struct variant.** A unit variant (`Ok`) or a tuple variant (`Ok(String)`) compiles fine and then fails every invocation with HTTP 500 `output_serialization_error`, because the variant payload must be a JSON object. A success variant with no ports is written `Ok {}`.
   - **Exactly one variant per response** — guaranteed by returning one enum value; nothing to do.
   - A port whose value is a JSON array becomes a `many` NexusData value; a scalar or object becomes `one`. Keep ports flat so downstream vertices can consume them directly.

3. **Wire up the real secrets.** Identify every secret the tool needs (API keys, OAuth tokens, connection strings, signing keys). For each: declare `static <NAME>: OnceLock<String>`, add `.set(load_required("<NAME>"))` to `validate_config`, add a private accessor function. Once real env vars are wired, delete every trace of the `EXAMPLE_API_KEY` scaffold — all three references: the `static EXAMPLE_API_KEY` declaration, the `EXAMPLE_API_KEY.set(...)` line inside `validate_config`, and the `example_api_key()` accessor function. **When a secret is needed, do not ask whether to put it in Input — the answer is always env var.** Log loads by name only: `log::debug!(target: "<tool>", "env var OPENAI_API_KEY loaded");`

   **nexus-tools mode only:** also update `<target-dir>/tests/toolkit_config_v2.rs` so its `.env(...)` calls match the new set of required vars exactly — a leftover `EXAMPLE_API_KEY` there is harmless, but a *missing* real var makes the test fail at startup. And update `<target-dir>/tools.json`'s `"environment"` map to reflect the real env var names. The map drives the deployment pipeline's secret injection — if it lists `EXAMPLE_API_KEY` (or is empty) but the code calls `load_required("OPENAI_API_KEY")`, deployment will inject the wrong var and `validate_config` will exit at startup. Add one entry per real env var; remove any leftover `EXAMPLE_API_KEY` entry.

4. **Add real dependencies** to `Cargo.toml` for any external calls. Defaults: `reqwest = { version = "0.12", features = ["json"] }` for HTTP, official SDK crates where they exist, `serde_json` for JSON shaping. In workspace mode prefer `*.workspace = true` if the dep is already in the upstream workspace; otherwise pin a major version.

5. **Implement `invoke()`** with the real logic. **Mandatory regardless of tool type:**
   - Access secrets only via the module-level accessors (`example_api_key()` etc.), NEVER `std::env::var` directly.
   - Map every distinct failure mode to a specific `Output::Err*` variant — do not collapse all errors into one generic variant.
   - Add `log::debug!` / `log::info!` / `log::warn!` / `log::error!` calls at entry, at key decision points, and before returning each output variant. `RUST_LOG` controls the level (`RUST_LOG=debug ./test.sh dev`). NEVER use `eprintln!` — it bypasses the log filter.
   - `invoke` does not return `Result` — failures are valid output variants returned as `Output::Err*`.

   **Additional, only if the tool makes external calls (HTTP, DB, gRPC, message-bus, etc.):**
   - Set an explicit timeout on every external call, and keep it **below** what `NexusTool::timeout()` returns. `timeout()` defaults to **10 seconds**, is published in `/meta`, and becomes the tool's registered on-chain timeout — a 30s client timeout under a 10s declared timeout means the runtime gives up before the tool can map the failure to an `err_*` variant. Either use a client timeout comfortably under 10s (e.g. `Duration::from_secs(8)`), or override `timeout()` on the impl to a value the upstream actually needs and set the client timeout under *that*. Upstream precedent for overriding: `offchain/tools/storage-walrus/src/*.rs`, `offchain/tools/llm-openai-chat-completion/src/main.rs`.
   - Wrap each I/O call so its failure modes map to specific `Output::Err*` variants — never let a raw HTTP/SDK error type leak as a string.

   **Pure-computation tools** (math, parsing, encoding, pure transformation — like upstream `tools/math`) skip the external-call bullets entirely. The mandatory bullets still apply.

6. **Implement `health()`** to probe every service the tool depends on (upstream API ping, DB connection check, etc.). Return `Err(...)` or a non-200 status if any dependency is down. A trivially-passing `health()` hides outages from Leader nodes, which is worse than no health check at all.

7. **Update tests.** One `#[tokio::test]` per output variant plus one `health()` test, minimum. Network-dependent tests: gate behind `#[ignore]` with a one-line explanation. Provide an offline test using a mock for the success path where feasible.

   **Rename the scaffold tests when you replace variants.** The template tests are named `invoke_returns_err_upstream` and `health_returns_ok` and assert against `Output::ErrUpstream`. When step 2 replaces `ErrUpstream`/`ErrConfig` with specific variants, rename and rewrite the tests to match — every Output variant should have at least one test, named after the variant it exercises.

   **Testing pattern for invoke() that uses accessors.** Skip this if the tool has no secrets (pure-computation tools that don't call any accessor — like upstream `tools/math`). For tools that do use accessors: once `invoke()` calls `example_api_key()` (or any accessor), tests that call `tool.invoke(input)` panic — the `OnceLock::get().expect(...)` fires because `validate_config` only runs in `main()`, not in `#[tokio::test]` runs. `validate_config` itself calls `std::process::exit(1)` on a missing var, which would kill the test runner. The idiomatic fix is to factor invoke's body into a private helper that takes the config as a parameter:

   ```rust
   async fn invoke(&self, input: Self::Input) -> Self::Output {
       invoke_impl(input, example_api_key()).await
   }

   async fn invoke_impl(input: Input, api_key: &str) -> Output {
       // all real logic here, parameterised on the config
   }
   ```

   Tests then call `invoke_impl(Input { ... }, "test-key").await` directly — no env vars, no panics, no `validate_config`. Apply the same factoring to `health()` if it uses accessors. Network-dependent tests that genuinely require a real key still need `#[ignore]` + env-var setup at the developer's machine.

8. **Update the README.** Replace the placeholder `Input` and `Output Variants & Ports` sections with the real shapes. Preserve the FQN-titled heading. **No `TODO` text may remain in the README.**

9. **Verify.** Run `cargo check`, `cargo test`, `cargo clippy`, and `cargo fmt --check` (from `offchain/` in nexus-tools mode when working from the repo root). Fix anything that fails before declaring Phase 7 done. If the `nexus` CLI is on PATH, also start the tool and run `nexus tool validate offchain --url http://localhost:8080/<what path() returns>` — it is the only check that catches an output enum the BCS encoder will reject at runtime. The path suffix is required; without it the CLI cannot find `/meta`. Also re-run the Phase 6 secrets scan against the real Input struct now that it has real fields (the Phase 4 scaffold had only `placeholder: String`, which was safe by construction — only post-step-1 Input fields can carry secrets violations):

   ```
   sed -n '/struct Input/,/^}/p' <target-dir>/src/<tool_name_snake>.rs \
     | grep -iE 'key|token|secret|password|credential|private|auth'
   ```

   Any match is a violation — apply the Phase 6 remediation steps (move to OnceLock+accessor).

**Completion gate.** Phase 7 is done only when ALL of the following hold (all greps use ERE / POSIX character classes so they work on both GNU and BSD grep):
- `grep -rnE '//[[:space:]]*TODO|^[[:space:]]*TODO:' <target-dir>/src <target-dir>/README.md` returns no matches. This catches `// TODO` comments in Rust and `TODO:` at line starts in markdown without false-positiving on legitimate words. (For pending work intentionally deferred to a later commit, use `// FIXME:` instead — it's not scanned by this gate.)
- No identifier named `placeholder` exists in the generated code: `grep -rnE '\bplaceholder\b' <target-dir>/src` returns no matches. (Real fields, vars, or function args must use domain-specific names.)
- No scaffold `#[allow(dead_code)]` markers remain: `grep -rnE '#\[allow\(dead_code\)\]' <target-dir>/src` returns no matches. Both scaffold markers (one on the `Output` enum, one on `example_api_key()`) should be deleted once their items are either used (every variant reachable, accessor called) or removed. If you ever need to keep a dead-code allowance on an output enum, put it on the **enum**, never on a variant — a variant-level attribute makes rustfmt expand every variant and `cargo fmt --check` fails.
- No `EXAMPLE_API_KEY` reference remains anywhere in the generated tool: `grep -rnE 'EXAMPLE_API_KEY|example_api_key' <target-dir>/src` returns no matches.
- `Output::Ok` carries the real success fields, not `result: String`.
- `invoke()` actually calls the described service or operates on the real inputs — not just logs and returns `ErrUpstream`.
- `cargo check`, `cargo test`, `cargo clippy`, `cargo fmt --check` all pass.

If any of these fail, Phase 7 is incomplete — keep working, do not advance to Phase 8.

### Phase 8 — Generate test script

Read the template from the skill's local installation. The skill's base directory is provided in the execution context — look for `Base directory for this skill:` in your active context. Read `<SKILL_BASE_DIR>/templates/test.sh` using the Read tool.

The template lives on disk next to this skill — no network call is needed or correct. If the base directory is not visible in the context, fall back in order:

- `gh api repos/Talus-Network/claude/contents/plugins/talus/skills/tool-new/templates/test.sh -H "Accept: application/vnd.github.raw"`
- WebFetch fallback: `https://raw.githubusercontent.com/Talus-Network/claude/main/plugins/talus/skills/tool-new/templates/test.sh`

The template contains four `__PLACEHOLDER__` markers. Substitute all four before writing:

| Placeholder | Value |
|---|---|
| `__TOOL_NAME__` | kebab-case crate name (= directory name); may be multi-segment per the workspace convention (e.g. `weather-open-meteo-forecast`, or `forecast` for a flat workspace) |
| `__TOOL_PATH__` | `tool_name_fqn_tail` from Phase 2 — the leaf action segment matching `path()` (e.g. `forecast`, `post-tweet`) |
| `__WORKSPACE_CARGO_DIR__` | relative path from the script to the cargo workspace root: `../..` for workspace mode (script at `…/tools/<tool_name>/test.sh`); `.` for standalone |
| `__SAMPLE_JSON__` | JSON object from the Input struct fields written in Phase 7. Map Rust types to plausible values: `String` → `"example"`, `i64`/`i32`/`u64`/`u32` → `42`, `f64`/`f32` → `1.0`, `bool` → `true`, `Option<T>` → inner type's value. For complex types (`serde_json::Value`, custom structs), ask the user for a concrete sample value. Omit any field marked `#[serde(skip)]`. If the Input struct is empty, use `{}`. The result must be valid JSON with no placeholder strings and **no single-quote characters** — the value is embedded in a single-quoted bash string in the template; a `'` inside it would terminate the string and break the script. |

Before writing, verify the substituted script has no bash syntax errors: `bash -n <path-to-substituted-content>`. If it fails, the `__SAMPLE_JSON__` substitution most likely introduced unbalanced quotes — fix the JSON before proceeding.

Write the substituted content to `<target-dir>/test.sh`, then `chmod +x <target-dir>/test.sh`.

After writing, print the examples to the user immediately — same output as `./test.sh start` would show — so they have the invocations at hand without running the script first.

**What the script does and does not check.** `./test.sh run` starts the server and runs `nexus tool validate offchain --url http://localhost:<port>/<tool_path>`, falling back to raw health and meta requests when the `nexus` CLI is not on PATH.

**The URL must include `path()`.** The toolkit mounts `/meta` and `/invoke` *under* each tool's `path()`. With `path()` returning `"/forecast"`, `/meta` at the root is a `405` and only `/forecast/meta` serves the metadata — so `nexus tool validate offchain --url http://localhost:8080` fails with *"failed to parse tool meta JSON: expected value at line 1 column 1"*, which looks like a broken tool and is not. Point the CLI at `http://localhost:8080/forecast`. Root `GET /health` works either way. The generated script derives this: it builds `TOOL_URL` from the port and `__TOOL_PATH__` and uses it for validation, `/meta`, and `/invoke`. The same applies when registering: `nexus tool register offchain --url` takes the path-scoped URL, and the register step preserves that path when composing the on-chain URL. It deliberately does **not** pipe `POST /invoke` into `jq`: a successful `/invoke` response is canonical BCS (`OffchainToolOutput`), not JSON, in every mode — signed HTTP disabled included. Only toolkit-level rejections come back as JSON (`input_deserialization_error`, `input_integrity_error`, `permission_denied`, `output_serialization_error`), which is why a JSON body from `/invoke` means the request was refused. If you hand-edit the generated script, preserve this: `curl … /invoke | jq .` prints binary garbage and reads as a broken tool.

The script's printed examples also include `<workspace>/target/debug/<tool_name> --meta | jq .`. `bootstrap!` intercepts `--meta`, prints a JSON array of each tool's metadata, and exits without binding a port — this is what CI feeds to `nexus tool register offchain --from-meta -`, and it is the fastest way to eyeball the generated input/output schemas.

**`just` integration (workspace mode + `just` on PATH from Phase 1)**

Read the existing `tools/.just` to understand the exact recipe format and parameter convention, then append four recipes following the same style. The `.just` file lives alongside the tool subdirectories (at `offchain/tools/.just`), and `just` runs each module recipe with the working directory set to the file's parent. So `cd {{tool}}` resolves to `<tool_name>/` relative to `offchain/tools/`. Do **not** prepend `tools/` or `offchain/tools/` — that is the working directory, not part of the cd target.

```
test-start tool:
    cd {{tool}} && ./test.sh start

test-stop tool:
    cd {{tool}} && ./test.sh stop

test-run tool:
    cd {{tool}} && ./test.sh run

test-dev tool:
    cd {{tool}} && ./test.sh dev
```

**Deployment reminders**

After printing the examples, surface these to the user. They are protocol invariants that apply to every off-chain Nexus Tool.

1. **The toolkit runtime is HTTP-only — put it behind a TLS terminator.** Leader nodes reach tools over HTTPS and validate the certificate against the system root trust store (same as `curl`); a self-signed certificate is rejected. Use Let's Encrypt or a cloud-managed certificate. Source: [tool-communication.md](https://github.com/Talus-Network/nexus-docs/blob/main/guides/tool-development/tool-communication.md).

2. **Signed HTTP is configured by a JSON file, not env vars.** The runtime reads its config from the path in `NEXUS_TOOLKIT_CONFIG_PATH`. If that variable is unset the runtime falls back to safe defaults with signed HTTP **disabled** — which is why local development and `./test.sh` work with no config at all. In production you mount a config file:

   ```json
   {
     "invoke_max_body_bytes": 10485760,
     "signed_http": {
       "mode": "required",
       "allowed_leaders_path": "./allowed_leaders.json",
       "tools": {
         "<the tool's FQN>": {
           "response_signing_key": "<32-byte ed25519 key, hex or base64>",
           "replay_cache_ttl_ms": 300000
         }
       }
     }
   }
   ```

   Points that bite in practice: `mode` defaults to `"required"` when the `signed_http` section is present at all, so a half-filled section fails closed; the section requires `allowed_leaders` or `allowed_leaders_path`, and a non-empty `tools` map, or the process refuses to start; `response_signing_key` is optional (without it the tool still authenticates callers, it just does not sign its results); `invoke_max_body_bytes` defaults to 10 MiB and `/invoke` **rejects any request without a `Content-Length` header**. Generate and register the keys with `nexus tool auth keygen`, `nexus tool auth register-key`, `nexus tool auth list-keys`, and export the allowlist with `nexus tool auth export-allowed-leaders`.

3. **Reverse proxy must forward `X-Nexus-Sig-*` headers.** Some API gateways strip unknown headers by default — verify yours passes them through. Do not use middleware that rewrites request or response bodies; the Ed25519 signature binds the raw bytes. Source: tool-communication.md.

4. **Keep the server clock NTP-synced.** Signed requests carry `iat_ms`/`exp_ms` validity windows; clock skew between your host and Leader nodes causes authentication failures.

5. **`health()` must check dependent services before deploying** — see Phase 7 step 6. A trivially-passing `health()` hides outages from Leader nodes. Source: [reference/toolkit/rust.md](https://github.com/Talus-Network/nexus-docs/blob/main/reference/toolkit/rust.md).

6. **Nonce deduplication is in-memory by default** (`replay_cache_ttl_ms`, 5 minutes). Sufficient for a single process. Behind a load balancer the cache is not shared across instances — use sticky sessions or a shared store so a replay routed elsewhere is still rejected. Source: tool-communication.md.

7. **Register, then verify.** The registration path is:

   ```sh
   # <path> is what path() returns — /meta and /invoke live under it, not at the root
   nexus tool validate offchain --url https://<host>/<path>   # health + meta + oneOf check
   nexus tool register offchain --url https://<host>/<path>   # or: --from-meta - (skips live HTTP)
                                 [--batch]                    # register every tool on the server
                                 [--invocation-cost <MIST>]   # defaults to 0
                                 [--collateral-coin <ID>]     # must differ from the gas coin
   nexus tool list
   nexus tool inspect --tool-fqn "<fqn>@1"
   ```

   Registration mints an `OwnerCap<OverTool>`; it is what authorizes `nexus tool unregister`, `nexus tool update-url`, `nexus tool update-timeout`, `nexus tool set-invocation-cost`, and `nexus tool claim-collateral` later. Registration is gated by an allowlist during beta — an authorization failure there usually means the address is not on it, not that the tool is wrong.

8. **Schema changes are breaking changes.** Adding a required input port, removing an output port, renaming a variant, or changing a type all change the contract DAGs depend on — publish as `…@2` and leave `…@1` registered. Non-contract changes (a bug fix in `invoke`, a faster implementation) can be redeployed under the same FQN. Source: [build-offchain-tool.md](https://github.com/Talus-Network/nexus-docs/blob/main/guides/tool-development/build-offchain-tool.md).

## Conventions (cited from upstream, summary)

From [build-offchain-tool.md](https://github.com/Talus-Network/nexus-docs/blob/main/guides/tool-development/build-offchain-tool.md):

- **Naming.** snake_case for input ports and output variants; descriptive over terse.
- **Errors.** Variants prefixed `err` are treated as erroneous by the Nexus runtime and have their ports propagated on-chain regardless of edges.
- **Output shape.** Top-level `oneOf` — enforced by the runtime, achieved in Rust via an enum.
- **Generic interface.** A tool encapsulates an API surface broadly, not one specific use case.
- **Flat output.** Output ports must be directly usable as input to another tool — no nested response objects.
- **Stable output.** Crucial data is non-optional; missing data → return an `err` variant instead of `ok` with `None`.
- **Docs.** Every tool has a README, included into `main.rs` via `#![doc = include_str!("../README.md")]`.

From [reference/toolkit/rust.md](https://github.com/Talus-Network/nexus-docs/blob/main/reference/toolkit/rust.md) — for the exact `NexusTool` trait method signatures consult upstream `tools/math/src/i64/add.rs` (the skill fetches it at every invocation; see Phase 4 verification step):

- **Stateless.** Tool structs should not carry mutable state across invocations. Per-startup config (env vars) is cached in module-level `OnceLock<String>` statics, populated once by `validate_config()` in `main()`. Anything per-request lives in the `Input` shape, not the struct.
- **`timeout()`.** Trait method with a **10-second default**, published in `/meta` and registered on-chain. Every external call the tool makes must complete inside it — override the method rather than letting a client timeout exceed the declared value. See Phase 7 step 5.
- **`authorize()`.** Optional hook, default allow, invoked only after signed HTTP has authenticated the request. Receives `AuthContext` (`= nexus_sdk::signed_http::v3::wire::AuthenticatedRequest`) carrying the verified invoker identity; returning `Err` produces a signed `403`. Implement when policy requires per-leader gating, allowlists, or rate limits.
- **`description()`.** Required, and part of the durable registry metadata users browse — SDK registration rejects blank descriptions.
- **Output encoding.** `/invoke` returns canonical BCS `OffchainToolOutput`, never JSON, in every mode. The enum must be externally tagged and every variant must be a struct variant. See Phase 7 step 2.
- **`bootstrap!` macro.** Accepts a single tool, `[Tool1, Tool2, ...]`, or `(socket_addr, [...])`. When multiple tools share a binary, each must have a unique `path()`. It calls `env_logger::try_init()` itself, reads `BIND_ADDR` (default `127.0.0.1:8080`), and intercepts `--meta` to print tool metadata as a JSON array and exit without serving.

## Failure modes

- **No network and no local clone.** Stop. Tell the user the skill needs one of them to fetch templates. Never fabricate.
- **`gh` not available but network is up.** Fall back to WebFetch on `raw.githubusercontent.com`.
- **`cargo` not on PATH.** Scaffold can still proceed, but Phase 6 verification cannot run — flag this clearly and ask the user how to proceed.
- **Existing files at the target path.** Never overwrite without explicit confirmation.
- **README "Adding a new tool" section not found (nexus-tools mode).** Do not stop. Generate the Phase 4.5 files from the reference tool (`offchain/tools/math/`) and tell the user the section is gone so they can check upstream for process changes.
- **README and reference tool disagree (nexus-tools mode).** The reference tool wins for file *shape*; the README wins for *process*. Say which one you followed and why. The known live case is `tools.json`, whose README example omits the `command` field that `build.rs` requires.
- **`/invoke` returns unreadable bytes.** That is correct — the success response is BCS, not JSON. A *readable* JSON body from `/invoke` means the toolkit rejected the request; read its `error` field.
- **`nexus tool validate offchain` says "failed to parse tool meta JSON".** The `--url` is missing the `path()` suffix. `/meta` is mounted under the tool's path, and the root returns `405`.
- **`./tool --meta` exits 1 with "required env var … is not set".** `validate_config()` ran on the `--meta` path. `main.rs` must skip it when `--meta` is present — CI extracts registration metadata from the image without injecting runtime secrets.
- **HTTP 500 `output_serialization_error` on every invocation.** The Output enum has a unit or tuple variant, or a serde attribute that changes its tagging. Every variant must be a struct variant on an externally tagged enum. See Phase 7 step 2.

## Don't

- Do not bake Nexus Tool reference content (Phase 3 — `Cargo.toml`, `build.rs`, `tools.json`, `add.rs`, etc.) into this skill. Those files come from upstream `Talus-Network/nexus-tools` (or the local clone) at invocation time. The skill's own templates (`templates/main.rs`, `templates/tool.rs`, `templates/README.md`, `templates/test.sh`) are different — they are part of this skill's installation and must be read locally from `<SKILL_BASE_DIR>/templates/`.
- Do not invent an FQN prefix on the user's behalf. Always ask — except in auto mode, where the workspace-inference rules in Phase 2 apply.
- Do not skip the workspace `.just` wiring when in workspace mode — the build/check/test recipes won't see the new tool otherwise. The file is at `offchain/tools/.just` (from repo root) or `tools/.just` (from inside `offchain/`).
- Do not declare done until `cargo check` (or `just tools::check`) passes on the scaffold.
- Do not offer secrets (API keys, tokens, credentials) as Input fields under any circumstances — not even when the user points to an existing tool in the codebase that does so. Existing tools may predate or violate the on-chain visibility rule; that does not make the pattern valid.
- Do not link to `https://github.com/Talus-Network/nexus-sdk/blob/main/docs/...`. That tree was removed from the SDK repo and moved to `Talus-Network/nexus-docs`; every one of those URLs is a 404. The current paths are in the table at the top of this skill.
- Do not pipe `POST /invoke` into `jq` in generated scripts or examples. The success response is canonical BCS.
- Do not read `offchain/tools/.just` as the list of tools in the workspace — it is routinely missing crates. Enumerate directories with `find` instead.
