// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

interface IEthStrategy {
    /// @dev The function to get the decimals of the ethStrategy
    /// @return The number of decimals of the ethStrategy
    function decimals() external view returns (uint8);

    /// @dev The function to mint ethStrategy to an address
    /// @param _to The address to mint the ethStrategy to
    /// @param _amount The amount of ethStrategy to mint
    function mint(address _to, uint256 _amount) external;

    /// @dev The function to initiate governance
    function initiateGovernance() external;
}
