// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {IEthStrategy} from "./interfaces/IEthStrategy.sol";
import {AtmAuction} from "./AtmAuction.sol";

contract Deposit is AtmAuction {
    /// @dev The maximum amount of ETH that can be deposited by a single user
    uint256 immutable MAX_DEPOSIT;
    /// @dev The error for when the deposit amount exceeds MAX_DEPOSIT

    error DepositAmountTooHigh();
    /// @dev The error for when the user attempts to initiate governance before the auction has ended
    error AuctionNotEnded();
    /// @dev The error for when the start price is not equal to the end price
    error InvalidStartEndPriceForDeposit();

    /// @notice The constructor for the Deposit contract
    /// @param _ethStrategy The address of the EthStrategy contract
    /// @param _paymentToken The address of the payment token
    /// @param _signer The address of the signer
    /// @param maxDeposit The maximum amount of the payment token that can be deposited by a single user
    constructor(address _ethStrategy, address _paymentToken, address _signer, uint256 maxDeposit)
        AtmAuction(_ethStrategy, _paymentToken, _signer)
    {
        MAX_DEPOSIT = maxDeposit;
        _setRoles(msg.sender, DA_ADMIN_ROLE);
    }

    /// @notice An internal function to fill the auction
    /// @param amountOut The amount of ethStrategy to be sold
    /// @param amountIn The amount of the payment token to be used as payment
    /// @param startTime The start time of the auction
    /// @param duration The duration of the auction
    function _fill(uint128 amountOut, uint256 amountIn, uint64 startTime, uint64 duration) internal override {
        super._fill(amountOut, amountIn, startTime, duration);
        if (amountIn > MAX_DEPOSIT) {
            revert DepositAmountTooHigh();
        }
    }

    /// @notice A function to start the auction
    /// @param _startTime The start time of the auction
    /// @param _duration The duration of the auction
    /// @param _startPrice The start price of the auction
    /// @param _endPrice The end price of the auction
    /// @param _amount The amount of ethStrategy to be sold
    function startAuction(uint64 _startTime, uint64 _duration, uint256 _startPrice, uint256 _endPrice, uint128 _amount)
        public
        override
        onlyOwnerOrRoles(DA_ADMIN_ROLE)
    {
        if (_startPrice != _endPrice) {
            revert InvalidStartEndPriceForDeposit();
        }
        super.startAuction(_startTime, _duration, _startPrice, _endPrice, _amount);
    }

    /// @notice A function to initiate governance (by anyone) after the auction has ended
    function initiateGovernance() external {
        if (auction.startTime != 0) {
            revert AuctionNotEnded();
        }
        IEthStrategy(ethStrategy).initiateGovernance();
    }
}
