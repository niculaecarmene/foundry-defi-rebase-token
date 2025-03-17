// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {console} from "forge-std/console.sol";


/**
 * @title RebaseToken
 * @dev RebaseToken contract is an ERC20 token with a fixed supply
 * @author Carmen
 * @notice This is a cross-chain rebase token, incentives user to deposit into a vault 
 * @notice the interest rate can only decrease. 
 * @notice each user will have their own interest rate, at the time of deposit.
 */
contract RebaseToken is ERC20, Ownable, AccessControl{


    /***********************
     * CONSTANTS           *
    ************************/
    uint256 public constant PRECISION_FACTOR = 1e18;
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    /***********************
     * ERROR DEFINITIONS   *
    ************************/
    error RebaseToken__InteresatRateCanOnlyDecrease(uint256 newRate, uint256 oldRate);

    /***********************
     * STATE VARIABLES     *
    ************************/
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; // 1e8 = 1 / 10ˆ-8
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdated;

    /***********************
     * EVENTS              *
    ************************/    
    event InterestRateSet(uint256 newRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender){

    }

    /***********************
     * PUBLIC FUNCTIONS    *
    ************************/

    /**
     * @notice returns the balance of the user including the interest
     * @param account the user to check the balance
     * @notice 1. get the balance of the user
     * @notice 2. calculate the interest of the user that was accumulate in the time since the last update
     * @return the balance of the user including the interest
     */
    function balanceOf(address account) public view override returns (uint256) {
        uint256 balance = super.balanceOf(account);
        if (balance == 0) {
            return 0;
        }
        console.log("RT.balanceOf(..) - balance", balance);
        uint256 interest = _calculateInterestSinceLastUpdate(account);
        console.log("RT.balanceOf(..) - interest", interest);
        uint256 result = (balance * interest) / PRECISION_FACTOR;
        console.log("RT.balanceOf(..) - result", result);
        return (balance * interest) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _recipient - the user who is receiving the tokens
     * @param _amount - the amount of tokens to transfer
     * @notice 1. mint the accrued interest to the sender
     * @notice 2. mint the accrued interest to the recipient
     * @notice 3. if the amount is the max, transfer the full balance
     * @notice 4. if the recipient has no balance, set the recipient interest rate to the sender interest rate
     * @return true if the transfer is successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _sender - the user who is sending the tokens
     * @param _recipient - the user who is receiving the tokens
     * @param _amount - the amount of tokens to transfer
     * @notice 1. mint the accrued interest to the sender
     * @notice 2. mint the accrued interest to the recipient
     * @notice 3. if the amount is the max, transfer the full balance
     * @notice 4. if the recipient has no balance, set the recipient interest rate to the sender interest rate
     * @return true if the transfer is successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        console.log("_sender",_sender);
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /***********************
     * EXTERNAL FUNCTIONS  *
    ************************/

    /**
     * @notice grant the mint and burn role to the account
     * @param _account the account to grant the mint and burn role
     */
    function grantMintAndBurnRole(address _account) public onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice set the interest rate
     * @param _interestRate the new interest rate
     * @dev the interest rate can only decrease
     */
    function setInterestRate(uint256 _interestRate) external onlyOwner{
        if (_interestRate >= s_interestRate) {
            revert RebaseToken__InteresatRateCanOnlyDecrease(_interestRate, s_interestRate);
        }
        s_interestRate = _interestRate;
        emit InterestRateSet(_interestRate);
    }

    /**
     * @notice mint the token to the user
     * @param _to the user to mint the token to
     * @param _amount the amount of token to mint
     * @notice 1. mint the accrued interest to the user
     * @notice 2. set the user interest rate to the current interest rate
     * @notice 3. mint the token to the user
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        console.log("START mint");
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        console.log("mint - before _mint");
        _mint(_to, _amount);
    }
    /*function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // Check if the user is new (has no principal balance)
        bool isNewUser = super.balanceOf(_to) == 0;

        // Mint accrued interest (does nothing for new users)
        _mintAccruedInterest(_to);

        // Set interest rate ONLY for new users
        if (isNewUser) {
            s_userInterestRate[_to] = s_interestRate;
        }

        // Mint the new tokens
        _mint(_to, _amount);
    }*/

    /**
     * @notice burn the user tokens when the withdraw from the vault
     * @param _from address of the user
     * @param _amount the withdraw amount
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice get the interest rate that is currently set for the contract, any future deposits will have this interest rate
     * @return the interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice get the balance of the user - including the interest that was accrued since the last interraction with the protocol.
     * @param _user the user to check the balance
     * @return the balance of the user
     */
    function principaleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }


    /***********************
     * INTERNAL FUNCTIONS  *
    ************************/

    /**
     * @param _user The user for whom we want to calculate the interest rate.
     * @return linearRate The interest that was accumulated since the last update.
     * @notice 1. Get the last updated timestamp of the user.
     * @notice 2. Calculate the time since the last update.
     * @notice 3. Calculate the amount of linear growth.
     */
    function _calculateInterestSinceLastUpdate(address _user) internal view returns (uint256 linearRate) {
        // deposit: 10 tokens
        // interest rate: 0.5%
        // time since last update: 2 seconds
        // interest = 10 * 0.5% * 2 = 0.1
        // total Balance = 10 + 10 * 0.5% * 2 = 10 (1 + 0.5% * 2)
        uint256 timeElapsed = block.timestamp - s_userLastUpdated[_user];
        linearRate = (s_userInterestRate[_user]*timeElapsed) + PRECISION_FACTOR;
    }

    /**
     * @notice mint the accrued interest to the user
     * @param _user the user to mint the interest to
     * @notice 1. find their current balance
     * @notice 2. calculate their current balance including any interest
     * @notice 3. calculate the number of tokens that need to be minted to the user
     * @notice 4. set the user last updated timestamp to the current timestamp
     */
    function _mintAccruedInterest(address _user) internal returns (uint256 balanceIncrease) {
        uint256 previousePrincipalBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        balanceIncrease = currentBalance - previousePrincipalBalance;
        _mint(_user, balanceIncrease);
        s_userLastUpdated[_user] = block.timestamp;
    }

    /***********************
     * GETTERS FUNCTIONS  *
    ************************/

    /**
     * @param _user return the interest rate of the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice checks if the sender had the MINT_AND_BURN_ROLE
     */
    function isGrantMintAndBurnRole() external view returns (bool){
        if (hasRole(MINT_AND_BURN_ROLE, msg.sender)){
            return true;
        }
        return false;
    }
}