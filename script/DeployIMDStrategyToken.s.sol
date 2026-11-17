// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {IMDStrategyToken} from "../src/IMDStrategyToken.sol";

/// @notice Reviewable deployment script. On the IMD launch the factory deploys the token itself
/// (the supply is minted to the factory); this script is for local or test-network use only.
/// It reads no environment variables and takes no configuration: the token has no parameters.
contract DeployIMDStrategyToken is Script {
    /// @notice Deploys the token; the whole supply is minted to the caller of this function's CREATE,
    /// i.e. this contract when called directly, or the broadcasting wallet under `run()`.
    function deploy() public returns (IMDStrategyToken token) {
        token = new IMDStrategyToken();
    }

    function run() external returns (IMDStrategyToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
