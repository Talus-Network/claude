/// `__COMPUTED_FQN__`
///
/// __DESCRIPTION__
module __MODULE_SNAKE__::__MODULE_SNAKE__;

use nexus_interface::onchain_tool_result::{Self as onchain_tool_result, OnchainToolResult};
use nexus_primitives::data;
use nexus_primitives::proof_of_uid::UIDRequirements;
use nexus_primitives::tagged_output;
use std::ascii::String as AsciiString;
use sui::bag::{Self, Bag};
use sui::transfer::share_object;

// === Structs ===

/// One-time witness for package initialization.
public struct __NAME_UPPER__ has drop {}

/// Witness object used as this Tool's execution stamp locator. It carries no
/// data — only its UID matters, and only for satisfying the requirement.
public struct __NAME_PASCAL__Witness has key, store {
    id: UID,
}

/// Shared state this Tool operates on.
public struct __NAME_PASCAL__State has key {
    id: UID,
    /// Holds the witness object that identifies this Tool.
    witness: Bag,
    // TODO: add this Tool's own state fields here, or delete this comment if
    // the Tool is stateless beyond the witness.
}

/// Declares the Tool's mutually exclusive output variants.
///
/// Registration derives the output schema from this enum; execution never
/// constructs it. Every variant and every field must mirror exactly what
/// `execute` can build via `tagged_output`, or the registered schema will not
/// match what DAGs actually receive.
///
/// Name failure variants with an `err` prefix — Nexus forwards their ports
/// on-chain regardless of edges, so downstream vertices can branch on them.
public enum Output {
    // TODO: replace with this Tool's real success ports.
    Ok {
        result: u64,
    },
    Err {
        reason: AsciiString,
    },
}

// === Public Functions ===

/// Executes the Tool.
///
/// The parameter prefix is the registration ABI and is validated by the SDK:
/// an owned `UIDRequirements` followed by an owned `OnchainToolResult`. Add
/// this Tool's own input ports and object arguments *after* that prefix and
/// before the trailing `ctx`. The function must be `public`, must return
/// nothing, and must not take any further framework parameters.
///
/// To gate the Tool so only authorized DAGs may call it, prepend an owned
/// `authorization: ProvenValue<AgentVertexAuthorization>` parameter and
/// consume it with `primitive_authorization::drop(authorization)`. The SDK
/// derives the registration mode from the signature — there is no CLI flag.
public fun execute(
    requirements: UIDRequirements,
    result: OnchainToolResult,
    state: &mut __NAME_PASCAL__State,
    // TODO: replace with this Tool's real input ports.
    input_value: u64,
    ctx: &mut TxContext,
) {
    let mut requirements = requirements;
    // REQUIRED: stamp the worksheet with this Tool's witness UID. Without it
    // the framework cannot prove the Tool ran and the walk fails.
    requirements.satisfy(&state.witness().id);

    // `TaggedOutput` has no `drop`, so every branch must produce one and hand
    // it to `finalize_and_share`. A branch that builds one and forgets it
    // fails to compile with `UnusedValueWithoutDrop`.
    //
    // Payload bytes are raw JSON: quote strings (`b"\"text\""`), leave numbers
    // and booleans unquoted.
    let output = if (input_value == 0) {
        // Return failure as routable Tool output instead of aborting — an
        // abort rolls back the whole walk and carries no data.
        tagged_output::new(b"err")
            .with_named_payload(
                b"reason",
                data::inline_data_value(b"\"input_value must be greater than zero\""),
            )
    } else {
        // TODO: implement the real logic.
        let computed = input_value * 2;
        tagged_output::new(b"ok")
            .with_named_payload(
                b"result",
                data::inline_data_value(computed.to_string().into_bytes()),
            )
    };

    onchain_tool_result::finalize_and_share(result, requirements, output, ctx);
}

// === View Functions ===

/// Returns the Tool witness object ID. This is the value
/// `nexus tool register onchain --tool-witness-id` expects — it is *not* the
/// shared state object ID.
public fun tool_witness_id(self: &__NAME_PASCAL__State): ID {
    object::uid_to_inner(&self.witness().id)
}

// === Private Functions ===

/// Creates the Tool's witness and shares its state object.
fun init(_otw: __NAME_UPPER__, ctx: &mut TxContext) {
    let state = __NAME_PASCAL__State {
        id: object::new(ctx),
        witness: {
            let mut bag = bag::new(ctx);
            bag.add(b"witness", __NAME_PASCAL__Witness { id: object::new(ctx) });
            bag
        },
    };
    share_object(state);
}

/// Borrows the witness object stored in the state bag.
fun witness(self: &__NAME_PASCAL__State): &__NAME_PASCAL__Witness {
    self.witness.borrow(b"witness")
}

// === Test Functions ===

#[test_only]
public fun init_for_test(otw: __NAME_UPPER__, ctx: &mut TxContext) {
    init(otw, ctx);
}
