// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {DutchAuction} from "./DutchAuction.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./EthStrategy.sol";

contract AtmAuction is DutchAuction {
    error AmountInValueTooLow();
    /// @dev The constructor for the AtmAuction contract, initializes the DutchAuction contract
    /// @param _ethStrategy The address of the EthStrategy contract
    /// @param _paymentToken The address of the payment token

    constructor(address _ethStrategy, address _paymentToken, address _signer)
        DutchAuction(_ethStrategy, _paymentToken, _signer)
    {}
    /// @dev An internal override of the _fill function from DutchAuction, transfers the paymentToken to the owner() and mints the EthStrategy tokens to the filler
    /// @param amountOut The amount of EthStrategy tokens to be sold
    /// @param amountIn The amount of payment tokens to be paid by the filler

    function _fill(uint128 amountOut, uint128 amountIn, uint64, uint64) internal virtual override {
        address _paymentToken = paymentToken;
        if (_paymentToken == address(0)) {
            if (msg.value < amountIn) {
                revert AmountInValueTooLow();
            }

            SafeTransferLib.safeTransferETH(owner(), amountIn);
            if (msg.value > amountIn) {
                uint256 refund = msg.value - amountIn;
                SafeTransferLib.safeTransferETH(msg.sender, refund);
            }
        } else {
            SafeTransferLib.safeTransferFrom(_paymentToken, msg.sender, owner(), amountIn);
        }
        IEthStrategy(ethStrategy).mint(msg.sender, amountOut);
    }
}
