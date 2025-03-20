// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract CrossChain is Test {

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    function setUp() public{
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepoliaFork = vm.createSelectFork("arb-sepolia");
    }
}