// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDStrategyToken} from "src/IMDStrategyToken.sol";

/// @dev The ghost ledger starts from the specified distribution and is updated from requested
/// actions, never from the token's resulting state. The token itself is a passive sixth holder;
/// it can receive tokens but is never impersonated to send its otherwise inaccessible balance.
contract IMDStrategyTokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IMDStrategyToken public immutable token;
    address[5] private actors;

    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public successfulCalls;
    uint256 public expectedReverts;
    bool public unexpectedOutcome;
    string public firstFailure;

    constructor(IMDStrategyToken token_, address[5] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = SUPPLY / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _recipient(toSeed), _transferAmount(amountSeed, expectedBalance[from]));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 allowanceSeed) external {
        address approvedSpender = spenderSeed % 6 == 5 ? address(0) : _actor(spenderSeed);
        uint256 choice = allowanceSeed % 5;
        uint256 amount = choice == 0
            ? 0
            : choice == 1 ? type(uint256).max : choice == 2 ? type(uint256).max - 1 : choice == 3 ? 1 : allowanceSeed;
        _approve(_actor(ownerSeed), approvedSpender, amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = ownerSeed % 6 == 5 ? address(0) : _actor(ownerSeed);
        _transferFrom(_actor(spenderSeed), from, _recipient(toSeed), _transferAmount(amountSeed, expectedBalance[from]));
    }

    /// @dev Creates reachable authorized calls, including full-balance and infinite approvals,
    /// instead of allowing every delegated transfer in the campaign to fail at allowance zero.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed, bool infinite)
        external
    {
        address from = _actor(ownerSeed);
        address approvedSpender = _actor(spenderSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        _approve(from, approvedSpender, infinite ? type(uint256).max : amount);
        _transferFrom(approvedSpender, from, _recipient(toSeed % 6), amount);
    }

    /// @dev Uses approvals left by earlier random actions without granting fresh authority.
    function spendExistingApproval(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address from = _actor(ownerSeed);
        address approvedSpender = _actor(spenderSeed);
        uint256 available = expectedBalance[from];
        uint256 approved = expectedAllowance[from][approvedSpender];
        if (approved < available) available = approved;
        _transferFrom(approvedSpender, from, _recipient(toSeed % 6), bound(amountSeed, 0, available));
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address from = _actor(ownerSeed);
        address approvedSpender = _actor(spenderSeed);
        _approve(from, approvedSpender, 0);
        _transferFrom(approvedSpender, from, _recipient(toSeed % 6), 1);
    }

    function selfTransfer(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        _transfer(actor, actor, _transferAmount(amountSeed, expectedBalance[actor]));
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _recipient(toSeed % 6), expectedBalance[from]);
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 fromIndex = fromSeed % actors.length;
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        _transfer(from, to, amount);
        _transfer(to, from, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        bytes memory expectedError;
        if (to == address(0)) {
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, to);
        } else if (amount > expectedBalance[from]) {
            expectedError = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount
            );
        }
        _invoke(from, abi.encodeCall(token.transfer, (to, amount)), expectedError);
        if (expectedError.length == 0) _move(from, to, amount);
    }

    function _approve(address owner, address approvedSpender, uint256 amount) private {
        bytes memory expectedError;
        if (approvedSpender == address(0)) {
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, approvedSpender);
        }
        _invoke(owner, abi.encodeCall(token.approve, (approvedSpender, amount)), expectedError);
        if (expectedError.length == 0) expectedAllowance[owner][approvedSpender] = amount;
    }

    function _transferFrom(address approvedSpender, address from, address to, uint256 amount) private {
        uint256 approved = expectedAllowance[from][approvedSpender];
        bytes memory expectedError;
        if (amount > approved) {
            expectedError = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, approvedSpender, approved, amount
            );
        } else if (from == address(0)) {
            // A zero-value spend still validates its allowance owner in _spendAllowance.
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, from);
        } else if (to == address(0)) {
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, to);
        } else if (amount > expectedBalance[from]) {
            expectedError = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount
            );
        }
        _invoke(approvedSpender, abi.encodeCall(token.transferFrom, (from, to, amount)), expectedError);
        if (expectedError.length == 0) {
            if (approved != type(uint256).max) expectedAllowance[from][approvedSpender] = approved - amount;
            _move(from, to, amount);
        }
    }

    function _move(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    /// @dev Persist failures instead of reverting the handler: fail_on_revert=false must never
    /// allow an assertion failure or an unexpected target revert to disappear from the campaign.
    function _invoke(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool ok, bytes memory returned) = address(token).call(data);
        if (expectedError.length == 0) {
            if (!ok || keccak256(returned) != keccak256(abi.encode(true))) {
                _markUnexpected("valid token call failed or did not return true");
            } else {
                ++successfulCalls;
            }
        } else if (ok || keccak256(returned) != keccak256(expectedError)) {
            _markUnexpected("invalid token call succeeded or returned the wrong error");
        } else {
            ++expectedReverts;
        }
    }

    function _markUnexpected(string memory reason) private {
        if (!unexpectedOutcome) firstFailure = reason;
        unexpectedOutcome = true;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _recipient(uint256 seed) private view returns (address) {
        uint256 index = seed % 7;
        if (index == 5) return address(token);
        if (index == 6) return address(0);
        return actors[index];
    }

    function _transferAmount(uint256 seed, uint256 balance) private pure returns (uint256) {
        uint256 choice = seed % 6;
        if (choice == 0) return 0;
        if (choice == 1) return 1;
        if (choice == 2) return balance;
        if (choice == 3) return balance + 1;
        if (choice == 4) return type(uint256).max;
        return bound(seed, 0, balance);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
contract IMDStrategyTokenInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IMDStrategyToken private token;
    IMDStrategyTokenHandler private handler;
    address[5] private actors;

    function setUp() public {
        actors = [
            makeAddr("invariant deployer"),
            makeAddr("invariant alice"),
            makeAddr("invariant bob"),
            makeAddr("invariant carol"),
            makeAddr("invariant spender")
        ];
        vm.startPrank(actors[0]);
        token = new IMDStrategyToken();
        for (uint256 i = 1; i < actors.length; ++i) {
            token.transfer(actors[i], SUPPLY / actors.length);
        }
        vm.stopPrank();

        handler = new IMDStrategyTokenHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.approveAndSpend.selector;
        selectors[4] = handler.spendExistingApproval.selector;
        selectors[5] = handler.revokeAndAttemptSpend.selector;
        selectors[6] = handler.selfTransfer.selector;
        selectors[7] = handler.transferAll.selector;
        selectors[8] = handler.roundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyEqualsAllBalancesAndGhostLedger() public view {
        assertEq(token.totalSupply(), SUPPLY, "fixed supply changed");
        uint256 sum = token.balanceOf(address(token));
        assertEq(sum, handler.expectedBalance(address(token)), "passive holder balance differs");
        for (uint256 i; i < actors.length; ++i) {
            uint256 actual = token.balanceOf(actors[i]);
            assertEq(actual, handler.expectedBalance(actors[i]), "actor balance differs from requested transfers");
            sum += actual;
        }
        assertEq(sum, SUPPLY, "tokens were created, destroyed or credited outside the recipients");
        assertEq(token.balanceOf(address(0)), 0, "zero address received tokens");
        assertEq(token.balanceOf(address(handler)), 0, "caller wrapper unexpectedly received tokens");
    }

    function invariant_allowancesMatchOnlyApprovalsAndSuccessfulSpends() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "allowance differs from approved and successfully spent amounts"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0, "invalid spender received approval");
            assertEq(token.allowance(address(0), actors[i]), 0, "invalid owner acquired an allowance");
        }
    }

    function invariant_validCallsSucceedAndInvalidCallsRevertExactly() public view {
        assertFalse(handler.unexpectedOutcome(), handler.firstFailure());
    }

    function invariant_metadataAndSupplyConstantsNeverChange() public view {
        assertEq(token.name(), "IMDStrategy");
        assertEq(token.TOKEN_NAME(), "IMDStrategy");
        assertEq(token.symbol(), "IMDSTR");
        assertEq(token.TOKEN_SYMBOL(), "IMDSTR");
        assertEq(token.decimals(), 18);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    function test_handlerExercisesEveryActionAndBothCallOutcomes() public {
        handler.transfer(0, 1, 1);
        handler.approve(1, 2, 1);
        handler.transferFrom(2, 1, 3, 1);
        handler.approveAndSpend(0, 2, 3, 123, false);
        handler.approveAndSpend(0, 2, 3, 123, true);
        handler.spendExistingApproval(0, 2, 1, 1);
        handler.revokeAndAttemptSpend(0, 2, 3);
        handler.selfTransfer(1, 2);
        handler.transferAll(3, 4);
        handler.roundTrip(4, 1, 123);
        handler.transfer(0, 6, 0);
        handler.approve(0, 5, 1);
        handler.transferFrom(2, 5, 1, 0);

        assertGt(handler.successfulCalls(), 0);
        assertGt(handler.expectedReverts(), 0);
        invariant_fixedSupplyEqualsAllBalancesAndGhostLedger();
        invariant_allowancesMatchOnlyApprovalsAndSuccessfulSpends();
        invariant_validCallsSucceedAndInvalidCallsRevertExactly();
        invariant_metadataAndSupplyConstantsNeverChange();
    }
}
