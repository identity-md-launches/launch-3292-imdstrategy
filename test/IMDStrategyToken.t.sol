// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDStrategyToken} from "../src/IMDStrategyToken.sol";
import {DeployIMDStrategyToken} from "../script/DeployIMDStrategyToken.s.sol";

contract IMDStrategyTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    IMDStrategyToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.prank(deployer);
        token = new IMDStrategyToken();
    }

    // ---------------------------------------------------------------- metadata & supply

    function test_metadata() public view {
        assertEq(token.name(), "IMDStrategy");
        assertEq(token.symbol(), "IMDSTR");
        assertEq(token.decimals(), 18);
    }

    function test_wholeSupplyMintedToDeployer() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, SUPPLY);
        vm.prank(alice);
        new IMDStrategyToken();
    }

    // ---------------------------------------------------------------- transfers

    function test_transferMovesExactAmount() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether)
        );
        vm.prank(alice);
        token.transfer(bob, 11 ether);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
    }

    function test_strangerCannotSpendWithoutBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transfer(alice, 1);
    }

    // ---------------------------------------------------------------- allowances

    function test_approveAndTransferFrom() public {
        vm.prank(deployer);
        assertTrue(token.approve(alice, 50 ether));
        assertEq(token.allowance(deployer, alice), 50 ether);

        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 20 ether));
        assertEq(token.balanceOf(bob), 20 ether);
        assertEq(token.allowance(deployer, alice), 30 ether);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1 ether));
        vm.prank(alice);
        token.transferFrom(deployer, alice, 1 ether);
    }

    function test_transferFromRevertsAboveAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 5 ether, 6 ether)
        );
        vm.prank(alice);
        token.transferFrom(deployer, alice, 6 ether);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1 ether);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    // ---------------------------------------------------------------- fixed supply / no admin

    function test_noAdminOrMintEntryPoints() public {
        string[8] memory sigs = [
            "mint(address,uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "owner()",
            "transferOwnership(address)",
            "blacklist(address)",
            "initialize(address)"
        ];
        for (uint256 i; i < sigs.length; ++i) {
            vm.prank(deployer);
            (bool ok,) = address(token).call(abi.encodeWithSignature(sigs[i], alice, SUPPLY));
            assertFalse(ok, sigs[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowance_);
        vm.prank(alice);
        if (amount > allowance_) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowance_, amount)
            );
            token.transferFrom(deployer, bob, amount);
        } else {
            token.transferFrom(deployer, bob, amount);
            assertEq(token.balanceOf(bob), amount);
            assertEq(
                token.allowance(deployer, alice), allowance_ == type(uint256).max ? allowance_ : allowance_ - amount
            );
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- deploy script

    function test_deployScriptMintsSupplyToCaller() public {
        DeployIMDStrategyToken script = new DeployIMDStrategyToken();
        IMDStrategyToken deployed = script.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(script)), SUPPLY);
        assertEq(deployed.name(), "IMDStrategy");
        assertEq(deployed.symbol(), "IMDSTR");
    }
}
