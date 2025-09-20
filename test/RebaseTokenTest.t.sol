// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RebaseToken} from "../src/RebaseToken.sol";
import {Test, console} from "forge-std/Test.sol";
import {IRebaseToken} from "../src/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Vault} from "../src/Vault.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract ReBaseTokenTest is Test {
    RebaseToken rbt;
    Vault vault;
    IRebaseToken irbt;
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rbt = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rbt)));
        rbt.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    function addRewardToVault(uint256 amount) public {
        (bool success,) = address(vault).call{value: amount}("");
    }

    function testBalanceIncreaseIinearlyWithTime(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rbt.balanceOf(user), amount);
        uint256 interestrate = rbt.getUserInterestRate(user);
        console.log("user", interestrate);
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rbt.balanceOf(user);
        assertGt(middleBalance, amount);
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rbt.balanceOf(user);
        assertGt(endBalance, middleBalance);
        assertApproxEqAbs(endBalance - middleBalance, middleBalance - amount, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rbt.balanceOf(user), amount);
        vault.redeem(type(uint256).max);
        assertEq(rbt.balanceOf(user), 0);
        assertEq(user.balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 amount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        amount = bound(amount, 1e5, type(uint96).max);
        vm.prank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        vm.warp(block.timestamp + time);
        uint256 balance = rbt.balanceOf(user);
        vm.deal(owner, balance - amount);
        vm.prank(owner);
        addRewardToVault(balance - amount);
        vm.prank(user);
        vault.redeem(type(uint256).max);
        uint256 ethBalance = user.balance;
        assertEq(ethBalance, balance);
        assertGt(ethBalance, amount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        address user2 = makeAddr("user2");
        vm.prank(user);
        rbt.transfer(user2, amountToSend);
        uint256 userBalance = rbt.balanceOf(user);
        uint256 user2Balance = rbt.balanceOf(user2);
        assertEq(amountToSend, user2Balance);
        assertEq(userBalance, amount - amountToSend);
        assertEq(rbt.getUserInterestRate(user2), 5e10);
        assertEq(rbt.getUserInterestRate(user), 5e10);
    }

    function testCanNotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rbt.setInterestRate(newInterestRate);
    }

    function testCanNotMintOrBurn() public {
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rbt.burn(user, 100);
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rbt.mint(user, 100, 5e5);
    }

    function testGetPrincipleAmount(uint256 amount) public {
        bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 principleBalance = rbt.getUserPrincipleBalance(user);
        assertEq(principleBalance, amount);
        vm.warp(block.timestamp + 1 hours);
        assertEq(principleBalance, amount);
    }

    function testVaultCanGetRebaseAddress() public view {
        address tokenAddress = vault.getRebaseTokenAddress();
        assertEq(tokenAddress, address(rbt));
    }

    function testInterestCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initalInterestRate = rbt.getCurrentInterestRate();
        newInterestRate = bound(newInterestRate, initalInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken_CanOnlyBeSetBelow.selector);
        rbt.setInterestRate(newInterestRate);
        assertEq(initalInterestRate, rbt.getCurrentInterestRate());
    }
}
