// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    uint256 public constant AMOUNT = 1000;
    uint256 public constant MIN_AMOUNT = 1e5;
    uint256 public constant MAX_AMOUNT = type(uint96).max;
    uint256 public constant MAX_MAX_AMOUNT = type(uint256).max;

    address public OWNER = makeAddr("OWNER"); 
    address public USER = makeAddr("USER");
    address public USER2 = makeAddr("USESR2");

    function setUp() public {
        vm.prank(OWNER);
        rebaseToken = new RebaseToken();
        vm.prank(OWNER);
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        vm.prank(OWNER);
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = address(vault).call{value: rewardAmount}("");
        console.log("addReward - success", success);
        require(success, "Failed to add rewards to the vault");
    }

    function testDepositLinier(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        
        // 1. deposit ETH
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();

        // 2. check the rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(USER);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);

        // 3. wrap the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(USER);
        assertGt(middleBalance, amount);

         // 4. wrap the time again and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(USER);
        assertGt(endBalance, middleBalance);
        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, MAX_AMOUNT);
        
        // 1. deposit ETH
        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(USER), amount);

        // 2. redeem the token
        vault.redeem(amount);
        assertEq(rebaseToken.balanceOf(USER), 0);
        assertEq(address(USER).balance, amount);
        vm.stopPrank();
    }

    function testReedemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, AMOUNT, MAX_AMOUNT);
        depositAmount = bound(depositAmount, MIN_AMOUNT, MAX_AMOUNT);
        
        // 1. deposit ETH
        vm.prank(USER);
        vm.deal(USER, depositAmount);
        vault.deposit{value: depositAmount}();
        assertEq(rebaseToken.balanceOf(USER), depositAmount);
  
        // 2. wrap the time 
        vm.warp(block.timestamp + time);

        // 2a. check the balance after some time
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(USER);

        // 2b. add rewards to the vault
        vm.prank(OWNER);
        uint256 addReward = balanceAfterSomeTime - depositAmount;
        vm.deal(OWNER, addReward);
        addRewardsToVault(addReward);

        // 3. redeem the token
        vm.prank(USER);
        vault.redeem(MAX_MAX_AMOUNT);
        
        // 4. check the balance
        uint256 ethBalance = address(USER).balance;
        assertEq(rebaseToken.balanceOf(USER), 0);
        assertEq(ethBalance, balanceAfterSomeTime);
    }

    function testTransfer(uint256 _amount, uint256 _amountToSend) public {
        _amount = bound(_amount, MIN_AMOUNT + MIN_AMOUNT, MAX_AMOUNT);
        _amountToSend = bound(_amountToSend, MIN_AMOUNT, _amount);

        // 1. deposit
        vm.prank(USER);
        vm.deal(USER, _amount);
        vault.deposit{value:_amount}();

        // 2. new user
        uint256 balanceUser = rebaseToken.balanceOf(USER);
        uint256 balanceUser2 = rebaseToken.balanceOf(USER2);
        assertEq(balanceUser, _amount);
        assertEq(balanceUser2, 0);

        // 3. owner decrease the interest rate
        vm.prank(OWNER);
        rebaseToken.setInterestRate(4e10);

        // 4. transfer
        vm.prank(USER);
        rebaseToken.transfer(USER2, _amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(USER);
        uint256 userBalanceAfterTransfer2 = rebaseToken.balanceOf(USER2);
        assertEq(userBalanceAfterTransfer, _amount - _amountToSend);
        assertEq(userBalanceAfterTransfer2, _amountToSend);

        // 5. check the user interest rates
        assertEq(rebaseToken.getUserInterestRate(USER), 5e10);
        assertEq(rebaseToken.getUserInterestRate(USER2), 5e10);
    }

    function testCannotSetInterestRateIfNotOwner(uint256 _newInterestRate) public {
        _newInterestRate = bound(_newInterestRate, 1e10, rebaseToken.getInterestRate()-1e10);
        vm.prank(USER);
        //vm.expectRevert("Ownable: caller is not the owner");
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(_newInterestRate);
    }

    function testCanootCallMintAndBurn() public{
        vm.prank(USER);
        vm.expectRevert();
        rebaseToken.mint(USER, 1000);
        vm.expectRevert();
        rebaseToken.burn(USER, 1000);
    }

    function testGetPrincipalAmount(uint256 _amount) public {
        _amount = bound(_amount, MIN_AMOUNT, MAX_AMOUNT);
        vm.deal(USER, _amount);
        vm.prank(USER);
        vault.deposit{value:_amount}();
        assertEq(rebaseToken.principaleBalanceOf(USER), _amount);
    }

    function testGetRebaseTokenAdr() public view {
        assertEq(vault.getRebaseTokenAdr(), address(rebaseToken));
    }

    function testInterestRateCanOnlyBeIncrease(uint256 _newInterestRate) public{
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        _newInterestRate = bound(_newInterestRate, initialInterestRate, MAX_AMOUNT);
        vm.prank(OWNER);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InteresatRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(_newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }


    function testTransferFrom() public {
        console.log("START TEST");
        vm.prank(OWNER);
        rebaseToken.grantMintAndBurnRole(USER);
        vm.prank(USER);
        console.log("BEFORE MINT - TEST", rebaseToken.isGrantMintAndBurnRole());
        vm.startPrank(USER);
        rebaseToken.mint(USER, 1000);
        console.log("testTransferFrom - after mint");
        rebaseToken.approve(USER, 500);
        rebaseToken.transferFrom(USER, USER2, 500);
        assertEq(rebaseToken.balanceOf(USER), 500);
        assertEq(rebaseToken.balanceOf(USER2), 500);
        vm.stopPrank();
    }

    function testMintBurnAccessControl() public {
        // 1. grant role to USER - so it can mint
        vm.prank(OWNER);
        rebaseToken.grantMintAndBurnRole(USER);

        // 2. user mints 1000
        vm.prank(USER);
        rebaseToken.mint(USER, AMOUNT);

        // 3. OWNER tries to mint for the USER, but it should be reverted, the balance of USER should stay 1000
        vm.prank(OWNER);
        vm.expectRevert();
        rebaseToken.mint(USER, AMOUNT);
        assertEq(rebaseToken.balanceOf(USER), AMOUNT);

        // 4. USER burns 1000
        vm.prank(USER);
        rebaseToken.burn(USER, AMOUNT);

        // 5. OWNER tries to burn 500 in USER's name, but it gets reverted, the balance of USER is 0
        vm.prank(OWNER);
        vm.expectRevert();
        rebaseToken.burn(USER, 500);
        assertEq(rebaseToken.balanceOf(USER), 0);
    }

    function testInterestAccrualWithTransfers() public {
        // 1. grant role to USER and USER2 - so it can mint
        vm.prank(OWNER);
        rebaseToken.grantMintAndBurnRole(USER);
        vm.prank(OWNER);
        rebaseToken.grantMintAndBurnRole(USER2);

        // 2. user mints 1000
        vm.prank(USER2);
        rebaseToken.mint(USER, AMOUNT);
        vm.warp(block.timestamp + 365 days);

        // 3. user2 tries to transfer 500
        vm.expectRevert();
        rebaseToken.transfer(USER2, 500);

        // 4. user burns 500
        vm.prank(USER);
        rebaseToken.burn(USER, 500);
        assertGt(rebaseToken.balanceOf(USER), 500);
        assertEq(rebaseToken.balanceOf(USER2), 0);
    }

    function testVaultWithdrawalInsufficientBalance() public {
        // 1. grant role to USER and USER2 - so it can mint
        vm.prank(OWNER);
        rebaseToken.grantMintAndBurnRole(USER);

        // 2. user mints 1000
        vm.prank(USER);
        rebaseToken.mint(USER, AMOUNT);
        //vm.expectRevert();
        vm.prank(USER);
        rebaseToken.transfer(USER2, AMOUNT);
    }
}
