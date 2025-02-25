// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {TReentrancyGuard} from "../lib/TReentrancyGuard/src/TReentrancyGuard.sol";
import {IEthStrategy} from "./EthStrategy.sol";

contract DutchAuction is OwnableRoles, TReentrancyGuard {
    error InvalidStartTime();
    error AuctionAlreadyActive();
    error AuctionNotActive();
    error InvalidStartPrice();
    error AmountExceedsSupply();
    error InvalidDuration();
    error AmountStartPriceOverflow();
    error AmountOutZero();
    error AmountBelowMinimum();
    error SlippageExceeded();
    error PriceCalculationOverflow();
    error MultiplicationOverflow();
    /// @dev The struct for the auction parameters

    struct Auction {
        uint64 startTime;
        uint64 duration;
        uint128 startPrice;
        uint128 endPrice;
        uint128 amount;
    }
    /// @dev The current auction

    Auction public auction;
    /// @dev The address of the EthStrategy contract (tokens to be sold)
    address public immutable ethStrategy;
    /// @dev The address of the payment token (tokens used as payment)
    address public immutable paymentToken;
    /// @dev The decimals of the EthStrategy token
    uint8 public immutable decimals;
    /// @dev The maximum start time window for an auction based on the current block time
    uint64 public constant MAX_START_TIME_WINDOW = 7 days;
    /// @dev The maximum duration for an auction to occur
    uint64 public constant MAX_DURATION = 30 days;
    /// @dev The minimum amount of tokens that can be filled
    uint128 public constant MIN_FILL_AMOUNT = 1e15; // 0.001 tokens with 18 decimals

    event AuctionStarted(Auction auction);
    event AuctionFilled(address buyer, uint128 amountOut, uint128 amountIn);
    event AuctionEndedEarly();
    event AuctionCancelled();
    /// @dev The role for the admin, can start and cancel auctions

    uint8 public constant ADMIN_ROLE = 1;

    /// @notice Constructor for the DutchAuction contract
    /// @param _ethStrategy The address of the EthStrategy contract (tokens to be sold)
    /// @param _paymentToken The address of the payment token (tokens used as payment)
    constructor(address _ethStrategy, address _paymentToken) {
        ethStrategy = _ethStrategy;
        paymentToken = _paymentToken;
        _initializeOwner(_ethStrategy);
        decimals = IEthStrategy(_ethStrategy).decimals();
    }
    /// @notice Start a new auction, auctions occur one at a time and can be triggered by the ADMIN_ROLE or the OWNER
    /// @param _startTime The start time of the auction
    /// @param _duration The duration of the auction
    /// @param _startPrice The starting price of the auction
    /// @param _endPrice The ending price of the auction
    /// @param _amount The amount of tokens to be sold

    function startAuction(uint64 _startTime, uint64 _duration, uint128 _startPrice, uint128 _endPrice, uint128 _amount)
        public
        onlyOwnerOrRoles(ADMIN_ROLE)
    {
        uint64 currentTime = uint64(block.timestamp);
        if (_startTime == 0) {
            _startTime = currentTime;
        }
        if (_startTime < currentTime || _startTime > currentTime + MAX_START_TIME_WINDOW) {
            revert InvalidStartTime();
        }
        if (_duration == 0 || _duration > MAX_DURATION) {
            revert InvalidDuration();
        }
        if (_startPrice > (type(uint128).max / _amount)) {
            revert AmountStartPriceOverflow();
        }
        Auction memory _auction = auction;
        if (_isAuctionActive(_auction, currentTime)) {
            revert AuctionAlreadyActive();
        }
        delete auction;
        if (_startPrice < _endPrice || _endPrice == 0) {
            revert InvalidStartPrice();
        }
        _auction = Auction({
            startTime: _startTime,
            duration: _duration,
            startPrice: _startPrice,
            endPrice: _endPrice,
            amount: _amount
        });
        auction = _auction;

        emit AuctionStarted(_auction);
    }

    /// @notice Cancel the current auction, can be triggered by the ADMIN_ROLE or the owner(), cancelling an auction will not effect tokens already sold
    function cancelAuction() public onlyOwnerOrRoles(ADMIN_ROLE) {
        delete auction;
        emit AuctionCancelled();
    }

    /// @notice Fill the auction with the amount of tokens to be sold
    /// @param _amountOut The amount of tokens to be sold
    /// @param _maxPrice The maximum price the buyer is willing to pay (slippage protection)
    function fill(uint128 _amountOut, uint128 _maxPrice) external nonreentrant {
        Auction memory _auction = auction;
        uint256 currentTime = block.timestamp;
        
        // Validate conditions
        _validateAuctionActive(_auction, currentTime);
        _validateFillAmount(_amountOut);
        _validateAmountNotExceedingSupply(_amountOut, _auction);
        
        // Calculate price
        uint128 currentPrice = _calculateCurrentPrice(_auction, currentTime);
        _validateSlippage(currentPrice, _maxPrice);
        
        // Calculate amount in
        uint128 amountIn = _calculateAmountIn(_amountOut, currentPrice);
        
        // Update state
        _updateAuctionState(_amountOut, _auction);
        
        // Execute fill
        _executeFill(_amountOut, amountIn, _auction.startTime, _auction.duration);
    }

    /// @notice Fill the auction with the amount of tokens to be sold (backward compatibility)
    /// @param _amountOut The amount of tokens to be sold
    function fill(uint128 _amountOut) external nonreentrant {
        Auction memory _auction = auction;
        uint256 currentTime = block.timestamp;
        
        // Validate conditions
        _validateAuctionActive(_auction, currentTime);
        _validateFillAmount(_amountOut);
        _validateAmountNotExceedingSupply(_amountOut, _auction);
        
        // Calculate price
        uint128 currentPrice = _calculateCurrentPrice(_auction, currentTime);
        
        // Calculate amount in
        uint128 amountIn = _calculateAmountIn(_amountOut, currentPrice);
        
        // Update state
        _updateAuctionState(_amountOut, _auction);
        
        // Execute fill
        _executeFill(_amountOut, amountIn, _auction.startTime, _auction.duration);
    }

    /// @dev An internal function to be called when the auction is filled, implementation left empty for inheriting contracts
    /// @param amountOut The amount of tokens to be sold
    /// @param amountIn The amount of tokens to be bought
    /// @param startTime The start time of the auction
    /// @param duration The duration of the auction
    function _fill(uint128 amountOut, uint128 amountIn, uint64 startTime, uint64 duration) internal virtual {}
    /// @dev Validates if the auction is active
    /// @param _auction The auction to check
    /// @param currentTime The current time
    function _validateAuctionActive(Auction memory _auction, uint256 currentTime) internal pure {
        if (!_isAuctionActive(_auction, currentTime)) {
            revert AuctionNotActive();
        }
    }

    /// @dev Validates if the fill amount is valid
    /// @param _amountOut The amount of tokens to be sold
    function _validateFillAmount(uint128 _amountOut) internal pure {
        if (_amountOut == 0) {
            revert AmountOutZero();
        }
        if (_amountOut < MIN_FILL_AMOUNT) {
            revert AmountBelowMinimum();
        }
    }

    /// @dev Validates if the amount does not exceed supply
    /// @param _amountOut The amount of tokens to be sold
    /// @param _auction The auction to check
    function _validateAmountNotExceedingSupply(uint128 _amountOut, Auction memory _auction) internal pure {
        if (_amountOut > _auction.amount) {
            revert AmountExceedsSupply();
        }
    }

    /// @dev Validates if the current price does not exceed the max price (slippage protection)
    /// @param currentPrice The current price of the auction
    /// @param maxPrice The maximum price the buyer is willing to pay
    function _validateSlippage(uint128 currentPrice, uint128 maxPrice) internal pure {
        if (currentPrice > maxPrice) {
            revert SlippageExceeded();
        }
    }

    /// @dev Updates the auction state based on the amount filled
    /// @param _amountOut The amount of tokens to be sold
    /// @param _auction The auction to update
    function _updateAuctionState(uint128 _amountOut, Auction memory _auction) internal {
        uint128 delta_amount = _auction.amount - _amountOut;
        if (delta_amount > 0) {
            auction.amount = delta_amount;
        } else {
            delete auction;
            emit AuctionEndedEarly();
        }
    }

    /// @dev Executes the fill operation
    /// @param _amountOut The amount of tokens to be sold
    /// @param amountIn The amount of tokens to be paid
    /// @param startTime The start time of the auction
    /// @param duration The duration of the auction
    function _executeFill(uint128 _amountOut, uint128 amountIn, uint64 startTime, uint64 duration) internal {
        emit AuctionFilled(msg.sender, _amountOut, amountIn);
        _fill(_amountOut, amountIn, startTime, duration);
    }

    /// @dev A helper function to check if the auction is active
    /// @param _auction The auction to check
    /// @param currentTime The current time
    /// @return bool true if the auction is active, false otherwise
    function _isAuctionActive(Auction memory _auction, uint256 currentTime) internal pure returns (bool) {
        return _auction.startTime > 0 && _auction.startTime + _auction.duration > currentTime
            && currentTime >= _auction.startTime;
    }
    /// @notice An external helper function to get the amount of tokens to be paid by the filler
    /// @param amountOut The amount of tokens to be sold
    /// @param currentTime The time the filler is calling the function
    /// @return amountIn The amount of tokens to be paid by the filler

    function getAmountIn(uint128 amountOut, uint64 currentTime) external view returns (uint128 amountIn) {
        Auction memory _auction = auction;
        uint128 currentPrice = _getCurrentPrice(_auction, currentTime);
        return _getAmountIn(amountOut, currentPrice);
    }
    /// @dev An internal helper function to get the amount of tokens to be paid by the filler
    /// @param amountOut The amount of tokens to be sold
    /// @param currentPrice The current price of the auction
    /// @return amountIn The amount of tokens to be paid by the filler

    /// @dev Calculates the amount of tokens to be paid by the filler with overflow checks
    /// @param amountOut The amount of tokens to be sold
    /// @param currentPrice The current price of the auction
    /// @return amountIn The amount of tokens to be paid by the filler
    function _calculateAmountIn(uint128 amountOut, uint128 currentPrice) internal view returns (uint128 amountIn) {
        // Check for multiplication overflow
        uint256 result = uint256(amountOut) * uint256(currentPrice);
        if (result / amountOut != currentPrice) {
            revert MultiplicationOverflow();
        }
        
        amountIn = uint128(result / (10 ** decimals));
        return (amountIn == 0) ? 1 : amountIn;
    }

    // Keep the original function for backward compatibility
    function _getAmountIn(uint128 amountOut, uint128 currentPrice) internal view returns (uint128) {
        return _calculateAmountIn(amountOut, currentPrice);
    }
    /// @dev An internal helper function to get the current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken
    /// @param _auction The auction to get the current price from
    /// @param currentTime The time the filler is calling the function
    /// @return currentPrice The current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken

    /// @dev Calculates the current price with improved precision
    /// @param _auction The auction to get the current price from
    /// @param currentTime The time the filler is calling the function
    /// @return currentPrice The current price of the auction
    function _calculateCurrentPrice(Auction memory _auction, uint256 currentTime)
        internal
        pure
        returns (uint128 currentPrice)
    {
        // Validate time is within auction period
        if (currentTime < _auction.startTime) {
            revert AuctionNotActive();
        }
        
        uint256 timeElapsed = currentTime - _auction.startTime;
        if (timeElapsed >= _auction.duration) {
            revert AuctionNotActive();
        }
        
        uint256 timeRemaining = _auction.duration - timeElapsed;
        
        // Calculate price with higher precision
        // (startPrice * timeRemaining + endPrice * timeElapsed) / duration
        uint256 numerator = uint256(_auction.startPrice) * timeRemaining + 
                           uint256(_auction.endPrice) * timeElapsed;
        
        uint256 price = numerator / _auction.duration;
        
        // Ensure the result fits in uint128
        if (price > type(uint128).max) {
            revert PriceCalculationOverflow();
        }
        
        return uint128(price);
    }

    // Keep the original function for backward compatibility
    function _getCurrentPrice(Auction memory _auction, uint256 currentTime)
        internal
        pure
        returns (uint128)
    {
        return _calculateCurrentPrice(_auction, currentTime);
    }
    /// @notice An external helper function to get the current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken
    /// @param currentTime The time the filler is calling the function
    /// @return currentPrice The current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken

    function getCurrentPrice(uint256 currentTime) external view returns (uint128 currentPrice) {
        Auction memory _auction = auction;
        _validateAuctionActive(_auction, currentTime);
        currentPrice = _calculateCurrentPrice(_auction, currentTime);
    }
    /// @dev An external helper function to check if the auction is active
    /// @param currentTime The time the filler is calling the function
    /// @return bool true if the auction is active, false otherwise

    function isAuctionActive(uint256 currentTime) external view returns (bool) {
        Auction memory _auction = auction;
        return _isAuctionActive(_auction, currentTime);
    }
}
