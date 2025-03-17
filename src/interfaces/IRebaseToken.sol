// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRebaseToken {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}
