// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRebaseToken {
    function mint(address account, uint256 amount, uint256 interestRate) external;
    function burn(address account, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function getUserInterestRate(address account) external view returns (uint256);
    function getInterestRate() external view returns (uint256);
}
