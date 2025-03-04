// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

interface IEthStrategy {
    function decimals() external view returns (uint8);
    function mint(address _to, uint256 _amount) external;
    function initiateGovernance() external;
}
