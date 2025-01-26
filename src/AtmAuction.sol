// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DutchAuction} from "./DutchAuction.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./DutchAuction.sol";

/**
 * @title AtmAuction
 * @notice Implements an ATM-style Dutch auction for minting EthStrategy tokens
 * @dev Inherits from DutchAuction and adds minting capability
 */
contract AtmAuction is DutchAuction {
    /// @notice Emitted when tokens are minted through the auction
    event TokensMinted(address indexed buyer, uint128 amount, uint128 price);
    
    /// @notice Emitted when a transfer fails
    error TransferFailed();
    
    /// @notice Emitted when mint fails
    error MintFailed();

    constructor(
        address _ethStrategy,
        address _governor,
        address _paymentToken
    ) DutchAuction(_ethStrategy, _governor, _paymentToken) {
        require(_ethStrategy != address(0), "Invalid strategy address");
        require(_governor != address(0), "Invalid governor address");
        require(_paymentToken != address(0), "Invalid payment token");
    }

    /**
     * @notice Internal function to fill an auction and mint tokens
     * @param amount Amount of tokens to mint
     * @param price Price per token
     * @param startTime Auction start time
     * @param duration Auction duration
     */
    function _fill(
        uint128 amount,
        uint128 price,
        uint64 startTime,
        uint64 duration
    ) internal override {
        require(amount > 0, "Amount must be positive");
        require(price > 0, "Price must be positive");
        
        super._fill(amount, price, startTime, duration);
        
        uint256 totalPayment = uint256(amount) * uint256(price);
        require(totalPayment / amount == price, "Arithmetic overflow");
        
        bool success = SafeTransferLib.safeTransferFrom(
            paymentToken,
            msg.sender,
            owner(),
            totalPayment
        );
        if (!success) revert TransferFailed();
        
        try IEthStrategy(ethStrategy).mint(msg.sender, amount) {
            emit TokensMinted(msg.sender, amount, price);
        } catch {
            revert MintFailed();
        }
    }
}