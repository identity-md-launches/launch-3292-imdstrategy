# IMDStrategy token tests

The original `IMDStrategyToken.t.sol` remains unchanged. `IMDStrategyToken.edges.t.sol`
adds unit and fuzz tests; `IMDStrategyToken.invariant.t.sol` adds the stateful handler
and its invariants. All dependencies are already vendored in this repository.

The property review used the five discovery perspectives in the supplied Pashov fizz
reference, and the supplied Trail of Bits guidance on bounded inputs, round trips,
independent oracles, and non-vacuous failure checks:

| Perspective | Property and basis | Coverage |
| --- | --- | --- |
| Conservation | The constructor mints exactly 1,000,000,000 × 10^18 once; balances sum to that fixed supply (`IMDStrategyToken` constructor and fixed-supply specification). | Invariants compare every tracked balance to a ghost ledger and sum all possible recipients. |
| State transitions | Approval replaces a single owner/spender entry; only successful delegated transfers spend it (inherited OpenZeppelin `approve`, `transferFrom`, `_spendAllowance`). | Approval isolation, replacement, revocation, exhaustion, infinite approval, and rollback on failed transfers. |
| Round trips | The token has no transfer fee or rounding (`IMDStrategyToken` inherits the unmodified ERC-20 transfer implementation). | Transfer and return restore balances exactly, including one minor unit and the full supply. |
| Adversarial inputs | Neither the deployer nor another spender has implicit authority over holders; insufficient balances/approvals and invalid recipients must revert (inherited ERC-20 requirements). | Unauthorized spending, replay after exhaustion, self-transfers above balance, zero addresses, maximum amounts, and finite/infinite allowance failures. |
| Token semantics | Valid zero transfers emit events without moving value; self-transfers preserve balances; finite approvals decrease while the maximum approval remains unchanged (inherited ERC-20 behavior). | Deterministic event and boundary tests, fuzz properties, and random action sequences. |

All asserted properties have a basis in the task's fixed-supply requirement or the
inherited ERC-20 interface and documented OpenZeppelin behavior. The tests do not
assume an extra owner, mint, burn, fee, or launch-time configuration.

The invariant handler uses five funded actors, including the deployer, and allows
the token contract to receive tokens as a passive sixth holder. Only the five actors
send calls; the token contract is never impersonated to recover its balance. The
recipient set is closed, making the sum-of-balances assertion complete for this
campaign. The ledger starts with the specified equal distribution and updates from
requested actions rather than learning expected balances from the implementation.

Nine actions mix direct transfers, approvals, delegated spending with existing and
new approvals, revocation, self-transfers, full-balance transfers, and round trips.
Input generation includes zero, one, the current full balance, balance plus one,
maximum uint256, and bounded amounts. Invalid actions check exact custom errors and
leave the ghost ledger unchanged. Unexpected results set a persistent flag checked
by an invariant, so ignored handler reverts cannot hide target call failures. A
deterministic smoke test exercises every action and both successful/reverting calls.

Fuzz tests run 1,000 examples each. Invariants run 256 sequences of 128 actions, with
run counts set inline in the test files. No production function checks `gasleft()`,
forwards gas, catches calls, or calls a recipient, so there is no applicable
`WalletGas.sol` call site. These tests need neither RPC access nor a fork.

Run locally, keeping generated artifacts in the disposable scratch directory:

```sh
forge build --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x38f63cad99959ef0b3e09c7b08ce5b80741643b26b70f2190609aa5e6db309cc \
  forge test --out test/scratch/out --cache-path test/scratch/cache
```
