// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title IMDStrategy (IMDSTR)
/// @notice Fixed-supply ERC-20. The whole supply of 1,000,000,000 tokens (18 decimals) is minted
/// once, in the constructor, to the deployer (`msg.sender`, which on launch is the factory).
/// @dev No owner, no mint, no burn, no pause, no blacklist, no fee: after construction the supply
/// can never change and only a holder (or a spender it approved) can move its balance.
contract IMDStrategyToken is ERC20 {
    /// @notice Token name returned by `name()`.
    string public constant TOKEN_NAME = "IMDStrategy";
    /// @notice Token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "IMDSTR";
    /// @notice The fixed total supply in minor units: 1,000,000,000 * 10**18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
