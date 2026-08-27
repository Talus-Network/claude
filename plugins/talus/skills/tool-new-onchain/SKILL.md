---
name: tool-new-onchain
description: Scaffold a new **on-chain** Nexus Tool as a Sui Move package and implement it end-to-end based on the user's description. An on-chain Tool is a Move module with a standardized public `execute` function that a workflow calls on Sui — use it when the Tool must mutate on-chain state, move assets, or be verifiable and atomic. Detects context: inside the Talus-Network/nexus-tools repo (or a fork) places the package at onchain/<tool-name>/; otherwise scaffolds a standalone Move package. Resolves the nexus_primitives and nexus_interface dependencies from a local nexus (nexus-next) checkout, a vendored deps/ tree, or a git revision. Verifies the scaffold with `sui move build` and `sui move test`, then walks publish and registration (`sui client publish`, `nexus tool register onchain`, `nexus tool validate onchain`). Use when the user asks to "create an onchain Nexus Tool", "scaffold a Move tool", "new Nexus Move tool", "build an on-chain tool", or similar. For an HTTP service in Rust that wraps an external API, use the `tool-new` skill instead.
argument-hint: "[--auto] [tool-name] [fqn-prefix] [description]"
allowed-tools: Bash(pwd) Bash(command -v *) Bash(head *) Bash(find *) Bash(grep *) Bash(sed -n *) Bash(cat *) Bash(sui move build*) Bash(sui move test*) Bash(sui client chain-identifier*) Bash(gh api *)
---

# `tool-new-onchain` — scaffold a new Nexus Tool in Move

An on-chain Nexus Tool is a Sui Move module whose `execute` function the Nexus workflow calls inside a programmable transaction block. Two ideas make a Move module a Tool:

- **It satisfies a requirement.** `execute` receives a `UIDRequirements` value and must satisfy it with the Tool's own witness UID. That is what proves to the framework the Tool actually ran.
- **It produces a durable result.** Instead of aborting on failure, `execute` builds a `TaggedOutput` whose tag and named payloads become the Tool's output variants and ports — exactly like an off-chain Tool's `Output` enum — then finalizes it into a shared `OnchainToolResult` the workflow consumes.

## Source of truth — read this before generating anything

The published guide for on-chain Tools has drifted from the code. **Verify every API against the sources below at invocation time; do not copy from documentation.**

**Authoritative (use these):**

| What | Where |
|---|---|
| The `execute` ABI the SDK actually validates | `nexus-sdk/sdk/src/onchain_schema_gen/input.rs`, fn `validate_execute_signature` |
| `data`, `tagged_output`, `proof_of_uid` Move APIs | a nexus (nexus-next) checkout: `sui/primitives/sources/{data,tagged_output,proof_of_uid}.move` |
| `onchain_tool_result` Move API | a nexus checkout: `sui/interface/sources/onchain_tool_result.move` |
| A complete worked Tool | a nexus checkout: `sui/examples/onchain_tool/sources/onchain_tool.move` |
| The CLI's own Move scaffold | `nexus-sdk/cli/src/tool/templates/move/tool.move.jinja` |
| Registration flags | `nexus-sdk/cli/src/tool/mod.rs`, `RegisterCommand::Onchain` |

**Known-stale — do not copy from these:**

- `nexus-docs/guides/tool-development/build-onchain-tool.md`. It shows `worksheet: ProofOfUID` with `stamp_with_data`, imports `onchain_tool_result` from `nexus_primitives`, depends on `nexus_workflow`, calls `data::inline_one(...)` with `.as_number()` / `.as_string()` type hints, declares `execute` as a bare `entry fun`, and passes `--workflow-authorization-cap-first` to `nexus tool register onchain`. **Every one of those is wrong against the current code.** If you consult it for prose, translate the APIs.
- Any `.move` file under a `build/` directory. Those are stale compilation artifacts, and their APIs differ from the `sources/` tree beside them.
- `nexus-tools/onchain/*/deps/` — vendored copies that may lag the packages they were copied from.

When you find a further discrepancy, follow the code and tell the user which document is out of date.

## The `execute` ABI

`validate_execute_signature` enforces all of the following. A violation is reported at `nexus tool register onchain` / `nexus tool validate onchain` time, not at compile time, so check it while generating:

1. **`public` visibility.** A bare `entry fun execute` fails — `entry` is not `public`. Use `public fun execute`.
2. **No return values.** Output is finalized through the owned `OnchainToolResult` argument.
3. **An owned `OnchainToolResult` parameter** — owned, not `&` or `&mut`.
4. **A fixed parameter prefix**, one of exactly two shapes, every parameter owned:

   | Mode | Prefix |
   |---|---|
   | `Standard` | `(requirements: UIDRequirements, result: OnchainToolResult, …)` |
   | `WorkflowAuthorization` | `(authorization: ProvenValue<AgentVertexAuthorization>, requirements: UIDRequirements, result: OnchainToolResult, …)` |

5. **No framework parameters after the prefix.** `AgentVertexAuthorization`, `ProofOfUID`, `UIDRequirements`, and `OnchainToolResult` may appear only inside the fixed prefix.

The Tool's own object arguments and input ports go **after** the prefix and **before** the trailing `ctx: &mut TxContext`.

**The mode is derived from the signature, not chosen at registration.** `nexus tool register onchain` has no mode flag and explicitly rejects `--workflow-authorization-cap-first`. Adding the `authorization` parameter is what opts the Tool into cap-gated registration; `nexus tool validate onchain` later cross-checks the registered mode against the live signature and fails if they disagree.

Choose `WorkflowAuthorization` when the Tool moves assets or mutates state that only authorized DAGs should be able to touch. Choose `Standard` otherwise. In auto mode: `WorkflowAuthorization` if the description mentions transferring, minting, burning, paying, or withdrawing; `Standard` otherwise. Print which mode was chosen and why.

## Arguments

Same parsing rules as `tool-new`:

```
/talus:tool-new-onchain counter-tool xyz.taluslabs.counter "Increments an on-chain counter"
/talus:tool-new-onchain --auto "Increments an on-chain counter"
```

- `tool_name` — kebab-case package name (e.g. `random-number`). Derived names: `module_snake` = hyphens → underscores (this is both the package name and the module name), `name_pascal` = PascalCase, `name_upper` = SCREAMING_SNAKE (the one-time witness).
- `fqn_prefix` — reverse-domain prefix without trailing dot. Never invent it outside auto mode — ask.
- `description` — required in all modes. Must not contain `"` or `\`; it is substituted into a Move doc comment and passed to `--description`.

**FQN grammar.** Splitting the full FQN on `.` must yield at least three parts, and every part must match `^[a-z][a-z0-9_-]+$` — lowercase, **at least two characters**, never starting with a digit, `-`, or `_`. Enforce this before generating.

**Auto mode** (`--auto` / `--yes`, or all three arguments given): skip every confirmation gate; infer what was not provided. Never overwrite an existing target directory without explicit confirmation, auto mode included.

## Context (computed at invocation)

- Working directory: !`pwd`

## Procedure

### Phase 1 — Detect context, placement, and dependencies

Run via Bash (all pre-authorized in `allowed-tools`):

1. `command -v sui` — empty means Phase 5 verification cannot run. Warn; the scaffold can still be written.
2. `command -v nexus` — empty means Phase 7 registration cannot run.
3. `find . -maxdepth 2 -path ./onchain -type d` — non-empty at a repo whose root also has `offchain/`: this is a nexus-tools checkout.
4. `find . -maxdepth 1 -name Move.toml -type f` — non-empty: already inside a Move package. Never nest a package inside another; place the new one as a sibling or ask.

Placement:

- **nexus-tools checkout:** `onchain/<tool-name>/`. Tell the user that `onchain/README.md` still describes the tree as reserved and that **there is no CI for it** — the `offchain/` pipeline (`tools.json`, `build.rs`, `.just` recipes, Docker, automatic registration) does not apply. Publishing and registration are manual, per Phase 7.
- **Anything else:** standalone package at `<tool-name>/` under the current directory.

Resolve the Nexus Move dependencies, in this order of preference:

1. **Local nexus checkout.** Look for a sibling `nexus`/`nexus-next` checkout containing `sui/primitives/Move.toml` and `sui/interface/Move.toml` (try `../nexus-next`, `../nexus`, `../../nexus-next`). Use `{ local = "<relative path>" }`. Best for development — it is the only option that stays in sync with the sources you read in Phase 3.
2. **Vendored `deps/`.** If a sibling package under `onchain/` carries `deps/primitives` and `deps/interface`, copy that arrangement. Warn that vendored copies drift.
3. **Git revision.** `{ git = "…", subdir = "sui/primitives", rev = "<tag>" }` pinned to the same tag the workspace targets.

If none can be resolved, stop and say so. Never fabricate a dependency path — the package will not build and the failure is confusing.

### Phase 2 — Resolve names and the FQN

- Compose `fqn_prefix` and the action segment the same way `tool-new` does: workspace root prefix from existing FQNs, then description-driven category and source segments. In a nexus-tools checkout, read existing on-chain FQNs from `onchain/*/Published.toml` (`[nexus.<env>] fqn = …`) and from `fqn` strings in sibling packages.
- Default the workspace root to `com.example` when nothing can be inferred, and print a warning to change it before publishing.
- Show the computed FQN and package directory. Confirm outside auto mode.

### Phase 3 — Read the reference sources

Read, in full, from a local nexus checkout when one was found in Phase 1, otherwise via `gh api` / WebFetch against the same paths:

- `sui/primitives/sources/data.move` — confirm the exact constructors. As of now: `inline_data_value(vector<u8>) -> NexusValue`, `object_value(ID) -> NexusValue`, `one(NexusValue) -> NexusData`, `many(vector<NexusValue>) -> NexusData`. There is **no** `inline_one` and **no** `.as_number()` / `.as_string()` type-hint API.
- `sui/primitives/sources/tagged_output.move` — `new(vector<u8>)`, `with_named_payload(name, NexusValue)`, `with_named_payload_many(name, vector<NexusValue>)`.
- `sui/primitives/sources/proof_of_uid.move` — `UIDRequirements` and `satisfy(&mut self, &UID)`.
- `sui/interface/sources/onchain_tool_result.move` — `finalize_and_share(result, requirements, output, ctx)`.
- `sui/examples/onchain_tool/sources/onchain_tool.move` — the worked reference.

If any signature differs from what this skill's template assumes, **the source wins**: adjust the generated file and tell the user what changed.

### Phase 4 — Generate files

Templates live on disk next to this skill. Look for `Base directory for this skill:` in the active context and read `<SKILL_BASE_DIR>/templates/<file>`. Fall back to `gh api repos/Talus-Network/claude/contents/plugins/talus/skills/tool-new-onchain/templates/<file> -H "Accept: application/vnd.github.raw"`, then WebFetch on `raw.githubusercontent.com`.

| Template | Target |
|---|---|
| `templates/tool.move` | `<target-dir>/sources/<module_snake>.move` |
| `templates/tests.move` | `<target-dir>/tests/<module_snake>_tests.move` |
| `templates/Move.toml` | `<target-dir>/Move.toml` |
| `templates/gitignore` | `<target-dir>/.gitignore` |

Placeholders — substitute every one before writing:

| Placeholder | Value |
|---|---|
| `__MODULE_SNAKE__` | `tool_name` with hyphens → underscores; package name and module name both |
| `__NAME_PASCAL__` | PascalCase of `__MODULE_SNAKE__`; struct name prefix |
| `__NAME_UPPER__` | SCREAMING_SNAKE_CASE of `__MODULE_SNAKE__`; the one-time witness type |
| `__DESCRIPTION__` | the description |
| `__COMPUTED_FQN__` | `<fqn_prefix>.<action>@1` |
| `__NEXUS_PRIMITIVES_DEP__` | the resolved dependency value from Phase 1, including braces, e.g. `{ local = "../../../nexus-next/sui/primitives" }` |
| `__NEXUS_INTERFACE_DEP__` | likewise for `interface` |
| `__ENV_ALIAS__` | environment alias, e.g. `nexus_testnet`. `testnet` and `mainnet` are reserved by the Sui toolchain and cannot be used |
| `__CHAIN_ID__` | the chain id from `sui client chain-identifier`. If no network is configured, leave the `[environments]` block out and tell the user to add it before registering |

After writing, confirm no markers remain — note that `<module_snake>_tests` legitimately contains no `__` pairs, so a plain grep is safe:

```
grep -rn '__[A-Z_]*__' <target-dir>
```

Empty output = success.

**WorkflowAuthorization mode only.** The template ships the `Standard` prefix. To switch, make exactly these three edits:

- add `use nexus_interface::authorization::AgentVertexAuthorization;` and `use nexus_primitives::authorization::{Self as primitive_authorization, ProvenValue};`
- prepend `authorization: ProvenValue<AgentVertexAuthorization>,` as the first parameter of `execute`
- add `primitive_authorization::drop(authorization);` as the first statement in the body

### Phase 5 — Verify the scaffold builds

```
cd <target-dir> && sui move build && sui move test
```

Both must pass before continuing. Common failures:

- **Unresolved dependency.** The `local` path in `Move.toml` is wrong relative to the package. Recheck against Phase 1.
- **`UnusedValueWithoutDrop`.** A branch of `execute` built a `TaggedOutput` and did not pass it to `finalize_and_share`. `TaggedOutput` has no `drop` ability; every branch must produce exactly one and finalize it.
- **Unknown function in `data` or `tagged_output`.** The resolved Nexus packages are a different version than the sources read in Phase 3. Align them.
- **Duplicate address / edition errors.** `[addresses]` must map `<module_snake> = "0x0"`, and `edition = "2024"`.

### Phase 6 — Implement

Replace the placeholders with real logic. The scaffold is a starting point, not the deliverable.

1. **Replace the input ports.** Add real parameters to `execute` after the fixed prefix. Primitive inputs become the Tool's input ports, supplied per invocation. Object arguments are supplied by the workflow when it assembles the call — prefer **shared** state (created with `share_object`) over owned objects, which couple the Tool to one submitting address.
2. **Replace the `Output` enum.** It is used **only** for schema generation at registration; the runtime consumes `OnchainToolResult`. It must nevertheless mirror exactly what `execute` can emit — every tag becomes a variant, every named payload becomes a field. A mismatch registers a schema DAGs cannot satisfy. Name failure variants with an `err` prefix; Nexus forwards their ports on-chain regardless of edges.
3. **Build the `TaggedOutput`.** `tagged_output::new(b"<tag>")` then `.with_named_payload(b"<port>", data::inline_data_value(<json bytes>))`, or `with_named_payload_many` for a `many` port. **Payload bytes are raw JSON:** a string must carry its own quotes (`b"\"text\""`), a number must not (`n.to_string().into_bytes()`), a bool is `b"true"` / `b"false"`.
4. **Never abort for a business-logic failure.** An abort rolls back the whole walk and carries no data; return an `err` variant instead so downstream vertices can branch. Reserve `assert!` for genuine invariant violations.
5. **Satisfy the requirement.** `requirements.satisfy(&state.witness().id)` must run on every path. Skipping it means the framework cannot verify execution and the walk fails.
6. **Emit events if useful.** A `has copy, drop` struct plus `sui::event::emit` makes executions observable to indexers. Events are independent of the result — `OnchainToolResult` drives DAG data flow.
7. **Write the tests.** `execute` cannot be called directly from a unit test: `UIDRequirements` and `OnchainToolResult` have no public test constructor. Factor the decision logic into a pure helper and test that, one test per output variant. Keep the scaffold's witness test — passing the shared state ID instead of the witness ID to `--tool-witness-id` is a real and silent failure mode.
8. **Write a README** at `<target-dir>/README.md`: the FQN as the top heading, an `## Input` section listing every port with its Move type, and an `## Output Variants & Ports` section listing every variant and its ports. Mirror the shape `tool-new` generates for off-chain Tools.

**Completion gate.** Phase 6 is done only when all of these hold:

- `grep -rnE '//[[:space:]]*TODO' <target-dir>/sources <target-dir>/tests` returns nothing.
- No identifier named `input_value` or `placeholder` remains from the scaffold.
- Every `Output` variant has a corresponding `tagged_output::new` tag in `execute`, and every variant field has a matching `with_named_payload` name.
- `sui move build` and `sui move test` both pass.

### Phase 7 — Publish and register

Walk the user through this; do not run the transactions unprompted — each one spends gas and needs a configured wallet.

```sh
sui client publish                      # note the package ID and the shared state object ID
sui client object <STATE_OBJECT_ID>     # read the witness ID out of the state's `witness` bag
```

The **tool witness ID** is the ID of the witness object inside the state's `Bag` — **not** the shared state object ID. `tool_witness_id()` is the getter that returns it.

```sh
nexus tool register onchain \
  --package "<PACKAGE_ID>" \
  --module <module_snake> \
  --tool-fqn "<fqn>@1" \
  --description "<description>" \
  --tool-witness-id "<WITNESS_ID>" \
  --timeout 5s
```

- `--timeout` defaults to `5s` and must be between `1s` and `2m`.
- `--collateral-coin <OBJECT_ID>` — the second owned `Coin<US>` is chosen automatically if omitted; it must not be the gas coin.
- `--invocation-cost <MIST>` — defaults to `0`. Keep it `0` while developing so sample DAGs run without charging callers.
- `--no-save` — skip writing the owner caps into the CLI config.
- There is **no** mode flag; the mode comes from the `execute` signature.

Registration mints an `OwnerCap<OverTool>`, which authorizes `nexus tool unregister`, `nexus tool set-invocation-cost`, `nexus tool update-timeout`, and `nexus tool claim-collateral` later. Registration is allowlist-gated during beta — an authorization failure there usually means the address is not on the list.

Verify:

```sh
nexus tool validate onchain --ident "<fqn>@1"
nexus tool inspect --tool-fqn "<fqn>@1"
nexus tool list
```

`validate onchain` re-derives the schema and mode from the live package and fails if they disagree with what was registered — run it after every republish.

**nexus-tools mode:** record the resulting IDs in `<target-dir>/Published.toml`, matching the shape a sibling package already uses (`[published.<env>]` with `chain-id`, `published-at`, `original-id`, `upgrade-capability`; `[objects.<env>]` with the state and witness IDs; `[nexus.<env>]` with `fqn`, `tool_id`, `owner_cap_over_tool_id`).

**Versioning.** Changing the input or output schema is a breaking change — publish as `…@2` and leave `…@1` registered so pinned DAGs keep working. A logic fix that preserves the schema can be republished under the same FQN, but must be re-validated.

Cross-reference [checklist.md](checklist.md) before declaring the Tool done.

## Failure modes

- **No local nexus checkout, no network.** Stop. The skill cannot resolve dependencies or read the reference sources. Never fabricate either.
- **`sui` not on PATH.** Scaffold can be written, but Phase 5 cannot run — flag it clearly and ask how to proceed.
- **Already inside a Move package.** Do not nest. Offer a sibling directory or abort.
- **Registration reports a signature error.** Re-read the ABI section above; the usual causes are `entry fun` instead of `public fun`, a `&`-borrowed `OnchainToolResult`, or a framework parameter placed after the fixed prefix.
- **`validate onchain` reports a mode mismatch.** The `authorization` parameter was added or removed after registration. Re-register under a new version.

## Don't

- Do not follow `build-onchain-tool.md`, or any `build/` artifact, for API shapes. See the source-of-truth table above.
- Do not pass `--workflow-authorization-cap-first` to `nexus tool register onchain` — the CLI rejects it. The mode comes from the signature.
- Do not declare `execute` as a bare `entry fun`. It must be `public`.
- Do not pass the shared state object ID as `--tool-witness-id`. It registers successfully and then never satisfies its requirement.
- Do not `abort` on a business-logic failure. Return an `err` variant.
- Do not apply the `offchain/` CI conventions (`tools.json`, `build.rs`, `.just`, `TOOL_FQN_VERSION`) to an on-chain package. They belong to the off-chain pipeline only.
