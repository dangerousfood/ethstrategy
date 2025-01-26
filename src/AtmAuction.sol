// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DutchAuction} from "./DutchAuction.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./DutchAuction.sol";
import {console} from "forge-std/console.sol";
contract AtmAuction is DutchAuction {

    constructor(address _ethStrategy, address _governor, address _paymentToken) DutchAuction(_ethStrategy, _governor, _paymentToken) {}

    function _fill(uint128 amount, uint128 price, uint64 startTime, uint64 duration) internal override {
      super._fill(amount, price, startTime, duration);
      uint256 amountToTransfer = amount * price / 10**decimals;
      console.log("amountToTransfer", amountToTransfer);
      console.log("decimals", decimals);
      console.log("amount", amount);
      SafeTransferLib.safeTransferFrom(paymentToken, msg.sender, owner(), amountToTransfer);
      IEthStrategy(ethStrategy).mint(msg.sender, amount);
    }
}

