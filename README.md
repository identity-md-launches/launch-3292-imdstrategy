# IMDStrategy (IMDSTR)

A fixed-supply ERC-20 token for a custom-token launch on Robinhood Chain (chain id 4663).

| Property        | Value                                                     |
|-----------------|-----------------------------------------------------------|
| Solidity name   | `IMDStrategyToken` (`src/IMDStrategyToken.sol`)           |
| `name()`        | `IMDStrategy`                                             |
| `symbol()`      | `IMDSTR`                                                  |
| `decimals()`    | `18`                                                      |
| `totalSupply()` | `1000000000000000000000000000` (1,000,000,000 × 10^18)    |
| Constructor     | no arguments                                              |
| Mint recipient  | `msg.sender` (the deployer, which is the launch factory)  |

## Behaviour

- The constructor mints the whole supply once, to the deployer. No other code path mints, so
  the supply cannot grow after that.
- The ERC-20 is plain OpenZeppelin v5.4.0 (`lib/openzeppelin-contracts`, vendored as ordinary files).
  It has no owner, admin, pause, blacklist, freeze, burn, fee, tax or transfer hook. Every
  transfer moves exactly the amount it says, so the launch flows go through unchanged: factory to
  MerkleDistributor, distributor to claimants, the seed into the Uniswap v4 PoolManager, and swaps
  both ways.
- The constructor calls no other contract and takes no arguments, so the launch can deploy it on an
  empty chain. Its runtime contains no DELEGATECALL, CALLCODE or SELFDESTRUCT.

## Build & test

```sh
forge build
forge test        # unit and fuzz tests in test/IMDStrategyToken.t.sol
forge fmt --check
```

`foundry.toml` pins `solc = "0.8.26"`, `evm_version = "cancun"` and `bytecode_hash = "none"`.
`lib/` vendors forge-std v1.11.0, OpenZeppelin Contracts v5.4.0, Uniswap v4-core (`src/` only)
and solmate's `Owned.sol`, which v4-core imports. The vendored v4-core and solmate are only there
so the launch's floor tests can build a PoolManager. The token does not use them.

The tests cover: the metadata; the supply and who receives it; the mint event; exact transfers;
reverts for insufficient balance, the zero receiver, a missing or exceeded allowance and the zero
spender; infinite allowance; that admin and mint entry points do not exist; fuzzed supply
conservation and allowance accounting; and the deploy script's `deploy()` function.

## Deployment parameters

- On the IMD launch, the factory deploys the token with `ProjectFactory.launchCustom` and no
  constructor arguments. The manifest records `token.contract = "IMDStrategyToken"`,
  `decimals = 18` and `totalSupply = "1000000000000000000000000000"`. The manifest step writes
  `launch.json` after this work is accepted, so this repository does not include one.
- The pool pairs with IMD (`0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` on chain 4663). The fee is
  12500 and the tick spacing is 60. Economics, as the requester gave them: `poolBps` 8000,
  `initialMarketCapWei` 3500000000000000000000, `remainderTo`
  `0xff3e8d9ba776662ca6ed1420ee366afb436d2684`. The factory sends 10% to the swarm's
  MerkleDistributor.
- `script/DeployIMDStrategyToken.s.sol` is for local or test-network use only. It reads no
  environment, and its `deploy()` function is tested directly.

## After launch

Nothing needs to be set. The token has no owner and no settable values.

## Assumptions and operational responsibilities

- Assumption: the brief asks for a plain fixed-supply token, so no fees, burns, vesting or
  governance were added.
- Nobody, including the requester and IMD, holds a privileged role over the token. So nobody can
  recover tokens sent to the wrong address, including tokens sent to the token contract itself.
- The requester is responsible for the allocation sent to `remainderTo` and for whatever is done
  with it after launch. Pool liquidity is managed by the launch factory, not by this token.
- Passing tests is not a security audit. The contract is unmodified OpenZeppelin ERC-20 code with
  a constructor mint. An independent review is still recommended before release.
