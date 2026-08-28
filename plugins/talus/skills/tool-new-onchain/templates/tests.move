#[test_only]
module __MODULE_SNAKE__::__MODULE_SNAKE___tests;

use __MODULE_SNAKE__::__MODULE_SNAKE__::{Self, __NAME_PASCAL__State, __NAME_UPPER__};
use sui::test_scenario;
use sui::test_utils;

const OWNER: address = @0xA;

// `execute` cannot be driven directly from a unit test: `UIDRequirements` and
// `OnchainToolResult` are framework-constructed values with no public test
// constructor. Cover the Tool's decision logic by factoring it out of
// `execute` into a pure helper and asserting on that here, then cover the
// full path with a DAG execution against a running network.
//
// TODO: add one test per output variant against that helper.

#[test]
fun init_shares_state_carrying_a_distinct_witness() {
    let mut scenario = test_scenario::begin(OWNER);
    {
        let otw = test_utils::create_one_time_witness<__NAME_UPPER__>();
        __MODULE_SNAKE__::init_for_test(otw, scenario.ctx());
    };
    scenario.next_tx(OWNER);
    {
        let state = scenario.take_shared<__NAME_PASCAL__State>();
        // The registration stamp locator is the witness UID, never the shared
        // state's own UID — passing the latter to `--tool-witness-id` produces
        // a Tool that registers but can never satisfy its requirement.
        assert!(object::id(&state) != __MODULE_SNAKE__::tool_witness_id(&state), 0);
        test_scenario::return_shared(state);
    };
    scenario.end();
}
