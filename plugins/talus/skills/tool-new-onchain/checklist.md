# Post-scaffold checklist — on-chain Tool

Walk through these after Phase 5 (`sui move build` and `sui move test` pass) and again after Phase 6. Each item is a property the package must satisfy.

## `<target-dir>/Move.toml`

- [ ] `[package].name` equals `module_snake` (the kebab-case tool name with hyphens → underscores)
- [ ] `edition = "2024"`
- [ ] `[dependencies]` declares `nexus_primitives` and `nexus_interface`, and nothing Nexus-related that the module does not actually use
- [ ] The dependency values resolve — `sui move build` proves it; a `local` path is relative to the package directory, not the repo root
- [ ] `[addresses]` maps `<module_snake> = "0x0"`
- [ ] `[environments]` maps an alias to the chain id from `sui client chain-identifier`. The alias is **not** `testnet` or `mainnet` — those are reserved by the Sui toolchain. Omit the block only if the user has no network configured yet, and say so

## `<target-dir>/sources/<module_snake>.move`

- [ ] Module doc comment starts with the FQN in backticks
- [ ] One-time witness `public struct <NAME_UPPER> has drop {}` exists and is consumed by `init`
- [ ] `public struct <NamePascal>Witness has key, store { id: UID }` — the stamp locator, carrying no data
- [ ] The state struct has `key`, holds the witness in a `Bag` under the key `b"witness"`, and is shared by `init` via `share_object`
- [ ] `public fun tool_witness_id(self: &<NamePascal>State): ID` returns the **witness** UID, not the state UID

### `execute` — the registration ABI

- [ ] Declared `public fun execute` — **not** a bare `entry fun`; `entry` alone is not `public` visibility and registration rejects it
- [ ] Returns nothing
- [ ] Takes an **owned** `OnchainToolResult` (no `&` or `&mut`)
- [ ] Parameter prefix is exactly one of:
  - [ ] `Standard`: `(requirements: UIDRequirements, result: OnchainToolResult, …)`
  - [ ] `WorkflowAuthorization`: `(authorization: ProvenValue<AgentVertexAuthorization>, requirements: UIDRequirements, result: OnchainToolResult, …)`
  every prefix parameter owned
- [ ] No `AgentVertexAuthorization`, `ProofOfUID`, `UIDRequirements`, or `OnchainToolResult` parameter appears **after** the fixed prefix
- [ ] The Tool's own object arguments and input ports sit between the prefix and the trailing `ctx: &mut TxContext`
- [ ] `WorkflowAuthorization` mode only: `primitive_authorization::drop(authorization)` is the first statement
- [ ] `let mut requirements = requirements;` then `requirements.satisfy(&state.witness().id);` runs on **every** path
- [ ] The body ends with `onchain_tool_result::finalize_and_share(result, requirements, output, ctx)`
- [ ] Every branch produces exactly one `TaggedOutput` and hands it to `finalize_and_share` — `TaggedOutput` has no `drop`, so a forgotten one fails to compile with `UnusedValueWithoutDrop`
- [ ] No `abort` or `assert!` for a business-logic failure — those return an `err` variant instead. `assert!` is reserved for genuine invariant violations

### Output shape

- [ ] `public enum Output` declares every variant `execute` can emit, and every named payload as a field. Registration derives the schema from this enum only — a mismatch registers a contract DAGs cannot satisfy
- [ ] Failure variants are prefixed `err`; Nexus forwards their ports on-chain regardless of edges
- [ ] Variant tags and port names are snake_case, and the `tagged_output::new(b"…")` tags match the enum variant names exactly
- [ ] Ports are flat — no nested objects
- [ ] Crucial ports are not optional; missing data surfaces as an `err` variant
- [ ] Payload bytes are valid raw JSON: strings carry their own quotes (`b"\"text\""`), numbers do not (`n.to_string().into_bytes()`), booleans are `b"true"` / `b"false"`
- [ ] Multi-valued ports use `with_named_payload_many`, not a hand-built array string

### API currency

- [ ] Uses `data::inline_data_value(...)` — **not** `data::inline_one(...)`, and no `.as_number()` / `.as_string()` / `.as_bool()` type-hint calls. Those come from a stale package version
- [ ] Imports `onchain_tool_result` from `nexus_interface`, not from `nexus_primitives`
- [ ] Takes `requirements: UIDRequirements` with `satisfy`, not `worksheet: ProofOfUID` with `stamp_with_data`
- [ ] Every one of the above was checked against the `sources/` tree of a real nexus checkout (or the equivalent via `gh api`), never against a `build/` artifact or `build-onchain-tool.md`

## `<target-dir>/tests/<module_snake>_tests.move`

- [ ] The one-time witness is built with `sui::test_utils::create_one_time_witness<NAME_UPPER>()` and passed to `init_for_test`
- [ ] A test asserts `tool_witness_id(&state)` differs from `object::id(&state)` — passing the state ID to `--tool-witness-id` registers successfully and then never satisfies the requirement
- [ ] The decision logic is factored into a pure helper and covered one test per output variant. `execute` itself cannot be unit-tested: `UIDRequirements` and `OnchainToolResult` have no public test constructor
- [ ] `sui move test` passes

## `<target-dir>/README.md`

- [ ] Top-level heading is the FQN in backticks
- [ ] `## Input` lists every input port with its Move type and description — no TODO text
- [ ] `## Output Variants & Ports` lists every variant and, for each, every port with type and description — no TODO text

## Placement

- [ ] nexus-tools checkout: the package is at `onchain/<tool-name>/`, and the user was told there is no CI for that tree
- [ ] **No** `tools.json`, `build.rs`, `[[bin]]`, `TOOL_FQN_VERSION`, or `.just` recipe was generated — those belong to the `offchain/` Rust pipeline only
- [ ] The package is not nested inside another Move package

## Naming

- [ ] Splitting the FQN on `.` yields at least three parts, and every part matches `^[a-z][a-z0-9_-]+$` — at least two characters, never starting with a digit, `-`, or `_`
- [ ] In a brand-new repo the workspace root fell back to `com.example` **and** a warning to change it before publishing was printed

## Verification

- [ ] `sui move build` passes
- [ ] `sui move test` passes
- [ ] `grep -rn '__[A-Z_]*__' <target-dir>` returns nothing
- [ ] After publish + register: `nexus tool validate onchain --ident "<fqn>@1"` passes. It re-derives the schema and mode from the live package and fails on any drift
- [ ] After publish + register: `nexus tool inspect --tool-fqn "<fqn>@1"` shows the expected ports
- [ ] nexus-tools mode: the package's `Published.toml` records the package, state, witness, and registration IDs
