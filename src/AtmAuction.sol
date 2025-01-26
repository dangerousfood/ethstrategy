// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DutchAuction} from "./DutchAuction.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./DutchAuction.sol";
contract AtmAuction is DutchAuction {

    constructor(address _ethStrategy, address _governor, address _paymentToken) DutchAuction(_ethStrategy, _governor, _paymentToken) {}

    function _fill(uint128 amount, uint128 price, uint64 startTime, uint64 duration) internal override {
      super._fill(amount, price, startTime, duration);
      SafeTransferLib.safeTransferFrom(paymentToken, msg.sender, owner(), amount * price / 10**decimals);
      IEthStrategy(ethStrategy).mint(msg.sender, amount);
    }
}

