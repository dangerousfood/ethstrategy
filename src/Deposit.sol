// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./EthStrategy.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {TReentrancyGuard} from "../lib/TReentrancyGuard/src/TReentrancyGuard.sol";
import {AtmAuction} from "./AtmAuction.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {console} from "forge-std/console.sol";

contract Deposit is AtmAuction {
    /// @dev The maximum amount of ETH that can be deposited
    uint256 constant MAX_DEPOSIT = 100e18;

    error DepositAmountTooHigh();
    error AuctionNotEnded();

    constructor(address _ethStrategy, address _paymentToken, address _signer)
        AtmAuction(_ethStrategy, _paymentToken, _signer)
    {}

    function _fill(uint128 amountOut, uint256 amountIn, uint64 startTime, uint64 duration) internal override {
        super._fill(amountOut, amountIn, startTime, duration);
        if (amountIn > MAX_DEPOSIT) {
            revert DepositAmountTooHigh();
        }
    }

    function initiateGovernance() external {
        if (auction.startTime != 0) {
            revert AuctionNotEnded();
        }
        IEthStrategy(ethStrategy).initiateGovernance();
    }
}
