// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDStrategyToken} from "src/IMDStrategyToken.sol";

contract IMDStrategyFactoryProbe {
    function deploy(bytes32 salt) external returns (IMDStrategyToken) {
        return new IMDStrategyToken{salt: salt}();
    }
}

/// forge-config: default.fuzz.runs = 1000
contract IMDStrategyTokenEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    IMDStrategyToken private token;
    address private deployer = makeAddr("edge deployer");
    address private alice = makeAddr("edge alice");
    address private bob = makeAddr("edge bob");
    address private spender = makeAddr("edge spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new IMDStrategyToken();
    }

    function test_create2MintsToFactoryAndDeploymentsAreIndependent() public {
        IMDStrategyFactoryProbe factory = new IMDStrategyFactoryProbe();
        vm.prank(alice);
        IMDStrategyToken first = factory.deploy(keccak256("first deployment"));
        IMDStrategyToken second = factory.deploy(keccak256("second deployment"));

        assertNotEq(address(first), address(second));
        assertEq(first.balanceOf(address(factory)), SUPPLY);
        assertEq(second.balanceOf(address(factory)), SUPPLY);
        assertEq(first.balanceOf(alice), 0);
        assertEq(first.balanceOf(address(this)), 0);
        vm.prank(address(factory));
        assertTrue(first.transfer(alice, SUPPLY));
        assertEq(first.balanceOf(alice), SUPPLY);
        assertEq(first.balanceOf(address(factory)), 0);
        assertEq(second.balanceOf(address(factory)), SUPPLY);
        assertEq(second.balanceOf(alice), 0);
        assertEq(first.totalSupply(), SUPPLY);
        assertEq(second.totalSupply(), SUPPLY);
    }

    function test_oneMinorUnitTransferEmitsExactEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, alice, 1);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsWithoutMovingTokens() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullSupplyCanMoveAndReturnWithoutTax() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullSupplySelfTransferEmitsAndLeavesBalanceUnchanged() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, deployer, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(deployer, SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferRevertsWithoutChangingBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
        _assertInitialBalances();
    }

    function test_zeroReceiverIsRejectedEvenForZeroTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(0)), 0);
        _assertInitialBalances();
    }

    function test_tokenContractCanHoldTokensWithoutBurningThem() public {
        vm.prank(deployer);
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalNeedsNoBalanceAndEmitsForMaximumAndRevocation() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, spender, type(uint256).max);
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.allowance(deployer, spender), 0);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, spender, 0);
        vm.prank(alice);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(alice, spender), 0);
        _assertInitialBalances();
    }

    function test_approvalOverwriteDoesNotAddOrReserveTokens() public {
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, 100));
        assertTrue(token.approve(spender, 7));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 7);
        _assertInitialBalances();
    }

    function test_revokedSpenderCannotSpendButNewApprovalWorks() public {
        vm.startPrank(deployer);
        token.approve(spender, type(uint256).max);
        token.approve(spender, 0);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        _assertInitialBalances();

        vm.prank(deployer);
        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 1));
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_exactAllowanceIsExhaustedAndCannotBeReused() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, bob, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.allowance(deployer, spender), 0);

        // Replenishing the owner does not replenish the spender's authority.
        vm.prank(bob);
        token.transfer(deployer, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(deployer), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_delegatedSelfTransferConsumesFiniteAllowanceOnly() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, deployer, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, SUPPLY));
        assertEq(token.allowance(deployer, spender), 0);
        _assertInitialBalances();
    }

    function test_ownerUsingTransferFromRequiresOwnAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
        _assertInitialBalances();

        vm.prank(deployer);
        token.approve(deployer, 1);
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_zeroTransferFromNeedsNoApprovalAndEmitsTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        _assertInitialBalances();
    }

    function test_zeroTransferFromRejectsZeroOwner() public {
        // OpenZeppelin validates the allowance owner before reaching the balance transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), bob, 0);
        assertEq(token.allowance(address(0), spender), 0);
        _assertInitialBalances();
    }

    function test_invalidRecipientRollsBackSpentAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 1);
        assertEq(token.allowance(deployer, spender), 1);
        assertEq(token.balanceOf(address(0)), 0);
        _assertInitialBalances();
    }

    function test_zeroTransferFromStillRejectsZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        _assertInitialBalances();
    }

    function test_maximumFiniteAllowanceIsDecremented() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, spender, SUPPLY));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(spender), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceSurvivesRepeatedSpendsAndBalanceFailure() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, bob, 1));
        assertTrue(token.transferFrom(deployer, bob, SUPPLY - 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, 0, 1));
        token.transferFrom(deployer, bob, 1);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalIsIsolatedByOwnerAndSpender() public {
        vm.prank(deployer);
        token.approve(spender, 9);
        vm.prank(alice);
        token.approve(bob, 7);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, spender), 9);
        assertEq(token.allowance(alice, bob), 7);
        assertEq(token.allowance(deployer, bob), 0);
        _assertInitialBalances();
    }

    function test_deployerCannotTakeBackHolderTokensWithoutApproval() public {
        vm.prank(deployer);
        token.transfer(alice, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);

        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripRestoresBalancesAndKeepsApproval(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, amount));
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        _assertInitialBalances();
    }

    function testFuzz_approveReplacementIsIdempotent(uint256 first, uint256 replacement) public {
        vm.startPrank(alice);
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(alice, spender), replacement);
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();
        assertEq(token.allowance(alice, spender), replacement);
        assertEq(token.allowance(deployer, spender), 0);
        _assertInitialBalances();
    }

    function testFuzz_partialSpendsCannotExceedAggregateApproval(uint256 approval, uint256 firstSpend) public {
        approval = bound(approval, 0, SUPPLY);
        firstSpend = bound(firstSpend, 0, approval);
        vm.prank(deployer);
        token.approve(spender, approval);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, firstSpend));
        assertEq(token.allowance(deployer, spender), approval - firstSpend);
        assertTrue(token.transferFrom(deployer, bob, approval - firstSpend));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, bob, 1);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), approval);
        assertEq(token.balanceOf(deployer), SUPPLY - approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_balanceFailureRollsBackFiniteAllowance(uint256 balance, uint256 requested) public {
        balance = bound(balance, 0, SUPPLY);
        requested = bound(requested, balance + 1, type(uint256).max - 1);
        vm.prank(deployer);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, requested);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, requested)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, requested);
        assertEq(token.allowance(alice, spender), requested);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(deployer), SUPPLY - balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_allowanceFailureLeavesEverythingUnchanged(uint256 approval, uint256 excess) public {
        approval = bound(approval, 0, SUPPLY - 1);
        uint256 requested = approval + bound(excess, 1, SUPPLY - approval);
        vm.prank(deployer);
        token.approve(spender, approval);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, requested)
        );
        vm.prank(spender);
        token.transferFrom(deployer, bob, requested);
        assertEq(token.allowance(deployer, spender), approval);
        _assertInitialBalances();
    }

    function testFuzz_selfTransfersNeverCreateBalance(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, amount));
        _assertInitialBalances();
    }

    function testFuzz_zeroSpenderCannotReceiveAnyApproval(uint256 amount) public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), amount);
        assertEq(token.allowance(deployer, address(0)), 0);
        _assertInitialBalances();
    }

    function _assertInitialBalances() private view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
    }
}
