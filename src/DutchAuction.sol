// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {TReentrancyGuard} from "../lib/TReentrancyGuard/src/TReentrancyGuard.sol";

interface IEthStrategy {
    function mint(address _to, uint256 _amount) external;
}

contract DutchAuction is OwnableRoles, TReentrancyGuard {
    error InvalidStartTime();
    error AuctionAlreadyActive();
    error AuctionNotActive();
    error InvalidStartPrice();
    error AmountExceedsSupply();
    error InvalidDuration();
    error AmountStartPriceOverflow();
    error AmountOutZero();
    error AmountInZero();

    struct Auction {
        uint64 startTime;
        uint64 duration;
        uint128 startPrice;
        uint128 endPrice;
        uint128 amount;
    }

    Auction public auction;

    address public immutable ethStrategy;
    address public immutable paymentToken;

    uint8 public immutable decimals;
    uint64 public constant MAX_START_TIME_WINDOW = 7 days;
    uint64 public constant MAX_DURATION = 30 days;

    event AuctionStarted(Auction auction);
    event AuctionFilled(address buyer, uint128 amountOut, uint128 amountIn);
    event AuctionEndedEarly();
    event AuctionCancelled();

    uint8 public constant ADMIN_ROLE = 1;

    constructor(address _ethStrategy, address _governor, address _paymentToken) {
        ethStrategy = _ethStrategy;
        paymentToken = _paymentToken;
        _initializeOwner(_governor);
        decimals = ERC20(_ethStrategy).decimals();
    }

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

    function cancelAuction() public onlyOwnerOrRoles(ADMIN_ROLE) {
        delete auction;
        emit AuctionCancelled();
    }

    function fill(uint128 _amountOut) public {
        Auction memory _auction = auction;
        uint256 currentTime = block.timestamp;
        if (!_isAuctionActive(_auction, currentTime)) {
            revert AuctionNotActive();
        }
        if (_amountOut == 0) {
            revert AmountOutZero();
        }
        if (_amountOut > _auction.amount) {
            revert AmountExceedsSupply();
        }
        uint128 currentPrice = _getCurrentPrice(_auction, currentTime);
        uint128 delta_amount = _auction.amount - _amountOut;
        if (delta_amount > 0) {
            auction.amount = delta_amount;
        } else {
            delete auction;
            emit AuctionEndedEarly();
        }
        uint128 amountIn = _getAmountIn(_amountOut, currentPrice);
        emit AuctionFilled(msg.sender, _amountOut, amountIn);
        _fill(_amountOut, amountIn, _auction.startTime, _auction.duration);
    }

    function _fill(uint128 amountOut, uint128 amountIn, uint64, uint64) internal virtual {}

    function _isAuctionActive(Auction memory _auction, uint256 currentTime) internal pure returns (bool) {
        return _auction.startTime > 0 && _auction.startTime + _auction.duration > currentTime
            && currentTime >= _auction.startTime;
    }

    function getAmountIn(uint128 amountOut, uint64 currentTime) external view returns (uint128 amountIn) {
        Auction memory _auction = auction;
        uint128 currentPrice = _getCurrentPrice(_auction, currentTime);
        return _getAmountIn(amountOut, currentPrice);
    }

    function _getAmountIn(uint128 amountOut, uint128 currentPrice) internal view returns (uint128 amountIn) {
        amountIn = uint128((amountOut * currentPrice) / 10 ** decimals);
        return (amountIn == 0) ? 1 : amountIn;
    }

    function _getCurrentPrice(Auction memory _auction, uint256 currentTime) internal pure returns (uint128) {
        uint256 delta_p = _auction.startPrice - _auction.endPrice;
        uint256 delta_t = _auction.duration - (currentTime - _auction.startTime);
        return uint128(((delta_p * delta_t) / _auction.duration) + _auction.endPrice);
    }

    function getCurrentPrice(uint256 currentTime) external view returns (uint128) {
        Auction memory _auction = auction;
        if (!_isAuctionActive(_auction, currentTime)) {
            revert AuctionNotActive();
        }
        return _getCurrentPrice(_auction, currentTime);
    }

    function isAuctionActive(uint256 currentTime) external view returns (bool) {
        Auction memory _auction = auction;
        return _isAuctionActive(_auction, currentTime);
    }
}
