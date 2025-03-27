// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {console} from "forge-std/console.sol";

/**
 * @title Vault
 * @author Carmen 
 * @notice pass the token address to the constructor
 * @notice create a deposit function that mints token to the user equal to the amount of ETH sent by the user
 * @notice create a redeem function that burns tokens from the user and sends the equivalent amount of ETH to the user
 * @notice create a way to add rewards to the user
 */

contract Vault {

    /***********************
     * ERROR DEFINITIONS   *
     ************************/
    error VAULT__REDEEM_FAILED();
    
    /***********************
     * IMMUTABLE VARIABLES *
     ************************/
    IRebaseToken private immutable i_rebaseToken;
    
    /***********************
     * STATE VARIABLES     *
    ************************/

    /***********************
     * EVENTS              *
     * **********************/
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    /***********************
     * MODIFIERS           *
     * **********************/

    constructor(IRebaseToken _rebaseTokenAdr) {
        i_rebaseToken = _rebaseTokenAdr;
    }

    /***********************
     * EXTERNAL FUNCTIONS   *
     * **********************/

    /**
     * @notice get the rebase token address
     * @return the rebase token address
     */
    function getRebaseTokenAdr() external view returns (address) {
        return address(i_rebaseToken);
    }

    /**
     * @notice allows users to deposit ETH and mint tokens in return
     */
    function deposit() external payable {
        // mint the user the amount of tokens equal to the amount of ETH sent
        // require the user to send at least 1 wei
        require(msg.value > 0, "Vault: deposit amount must be greater than 0");
        // mint the user the amount of tokens equal to the amount of ETH sent
        // get the amount of tokens to mint
        // mint the tokens to the user

        console.log("vault - interestrate", i_rebaseToken.getInterestRate());
        i_rebaseToken.mint(msg.sender, msg.value);
        console.log("vault - user address", msg.sender);
        console.log("vault - user interestrate after mint", i_rebaseToken.getUserInterestRate(msg.sender));
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice allows users to deposit ETH and redeem tokens in return
     * @param _amount the amount of tokens to redeem
     */
    function redeem(uint256 _amount) external {
        console.log("V.redeem BEGIN");
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }   
        console.log("V.redeem - _amount", _amount);
        // burn the amount of tokens from the user
        // send the equivalent amount of ETH to the user
        // burn the tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // send the equivalent amount of ETH to the user
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert VAULT__REDEEM_FAILED();
        }
        emit Redeem(msg.sender, _amount);
    }

    receive() external payable {}   
}