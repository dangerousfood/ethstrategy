// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {TReentrancyGuard} from "../lib/TReentrancyGuard/src/TReentrancyGuard.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";

contract DutchAuction is OwnableRoles, TReentrancyGuard {
    /// @dev The error for when the start time is before the current block time or more than 7 days in the future
    error InvalidStartTime();
    /// @dev The error for when the DA_ADMIN_ROLE calls startAuction while the auction is already active
    error AuctionAlreadyActive();
    /// @dev The error for when a user attempts to fill an auction has not begun or is already over
    error AuctionNotActive();
    /// @dev The error for when the end price is greater than the start price or the end price is zero
    error InvalidStartPrice();
    /// @dev The error for when the provided fill amount exceeds the auction supply
    error AmountExceedsSupply();
    /// @dev The error for when the duration is zero or greater than 30 days
    error InvalidDuration();
    /// @dev The error for when the start price multiplied by the amount exceeds the max uint256 value
    error AmountStartPriceOverflow();
    /// @dev The error for when the provided fill amount is zero
    error AmountOutZero();
    /// @dev The error for when a user has already redeemed a whitelist spot
    error AlreadyRedeemed();
    /// @dev The error for when the signature is invalid
    error InvalidSignature();
    /// @dev The error for when a user attempts to call a payable method that is not receive()
    error InvalidCall();

    /// @dev The struct for the auction parameters
    struct Auction {
        uint64 startTime;
        uint64 duration;
        uint128 amount;
        uint256 startPrice;
        uint256 endPrice;
    }

    /// @dev The current auction
    Auction public auction;
    /// @dev The address of the EthStrategy contract (tokens to be sold)
    address public immutable ethStrategy;
    /// @dev The address of the payment token (tokens used as payment)
    address public immutable paymentToken;
    /// @dev The decimals used for price evaluation
    uint8 public constant decimals = 18; // percentage in basis points
    /// @dev The maximum start time window for an auction based on the current block time
    uint64 public constant MAX_START_TIME_WINDOW = 7 days;
    /// @dev The maximum duration for an auction to occur
    uint64 public constant MAX_DURATION = 30 days;
    /// @dev The address of the whitelist signer
    address public signer;

    /// @dev A mapping to track if a user has redeemed whitelist spot
    mapping(bytes32 => bool) public hasRedeemed;

    /// @dev The event for when an auction is started
    event AuctionStarted(Auction auction);
    /// @dev The event for when an auction is filled
    event AuctionFilled(address buyer, uint128 amountOut, uint256 amountIn);
    /// @dev The event for when an auction is ended early (all tokens sold)
    event AuctionEndedEarly();
    /// @dev The event for when an auction is cancelled
    event AuctionCancelled();

    /// @dev The role for the dutch auction admin, can start and cancel auctions
    uint256 public constant DA_ADMIN_ROLE = uint256(keccak256("DA_ADMIN_ROLE"));

    /// @notice Constructor for the DutchAuction contract
    /// @param _ethStrategy The address of the EthStrategy contract (tokens to be sold)
    /// @param _paymentToken The address of the payment token (tokens used as payment)
    constructor(address _ethStrategy, address _paymentToken, address _signer) {
        ethStrategy = _ethStrategy;
        paymentToken = _paymentToken;
        _initializeOwner(_ethStrategy);
        _setRoles(msg.sender, DA_ADMIN_ROLE);
        signer = _signer;
    }

    /// @notice Start a new auction, auctions occur one at a time and can be triggered by the ADMIN_ROLE or the owner()
    /// @param _startTime The start time of the auction
    /// @param _duration The duration of the auction
    /// @param _startPrice The starting price of the auction
    /// @param _endPrice The ending price of the auction
    /// @param _amount The amount of tokens to be sold
    function startAuction(uint64 _startTime, uint64 _duration, uint256 _startPrice, uint256 _endPrice, uint128 _amount)
        public
        virtual
        onlyOwnerOrRoles(DA_ADMIN_ROLE)
    {
        uint64 currentTime = uint64(block.timestamp);
        if (_startTime == 0) {
            _startTime = currentTime;
        }
        /// @dev prevent auctions starting in the past or more than 7 days in the future
        if (_startTime < currentTime || _startTime > currentTime + MAX_START_TIME_WINDOW) {
            revert InvalidStartTime();
        }
        /// @dev prevent auctions with a duration of zero or greater than 30 days
        if (_duration == 0 || _duration > MAX_DURATION) {
            revert InvalidDuration();
        }
        /// @dev prevent the start price multiplied by the amount from overflowing
        if (_startPrice > (type(uint256).max / _amount)) {
            revert AmountStartPriceOverflow();
        }
        Auction memory _auction = auction;
        /// @dev prevent auctions from being started while another is active
        if (_isAuctionActive(_auction, currentTime)) {
            revert AuctionAlreadyActive();
        }
        delete auction;
        /// @dev prevent the start price from being less than the end price or the end price from being zero
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
    function cancelAuction() public onlyOwnerOrRoles(DA_ADMIN_ROLE) {
        delete auction;
        emit AuctionCancelled();
    }

    /// @notice Fill the auction with the amount of tokens to be sold
    /// @param _amountOut The amount of tokens to be sold
    /// @param signature The signature of the whitelist spot for the msg.sender
    function fill(uint128 _amountOut, bytes calldata signature)
        external
        payable
        virtual
        nonreentrant
        whitelist(signature)
    {
        Auction memory _auction = auction;
        uint256 currentTime = block.timestamp;
        /// @dev prevent the user from filling an inactive auction
        if (!_isAuctionActive(_auction, currentTime)) {
            revert AuctionNotActive();
        }
        /// @dev prevent the user from filling an auction with an amount of zero
        if (_amountOut == 0) {
            revert AmountOutZero();
        }
        /// @dev prevent the user from filling an auction with an amount of tokens that exceeds the auction supply
        if (_amountOut > _auction.amount) {
            revert AmountExceedsSupply();
        }
        uint256 currentPrice = _getCurrentPrice(_auction, currentTime);
        uint128 delta_amount = _auction.amount - _amountOut;
        if (delta_amount > 0) {
            auction.amount = delta_amount;
        } else {
            delete auction;
            emit AuctionEndedEarly();
        }
        uint256 amountIn = _getAmountIn(_amountOut, currentPrice);
        emit AuctionFilled(msg.sender, _amountOut, amountIn);
        _fill(_amountOut, amountIn, _auction.startTime, _auction.duration);
    }

    /// @dev An internal function to be called when the auction is filled, implementation left empty for inheriting contracts
    /// @param amountOut The amount of tokens to be sold
    /// @param amountIn The amount of tokens to be bought
    /// @param startTime The start time of the auction
    /// @param duration The duration of the auction
    function _fill(uint128 amountOut, uint256 amountIn, uint64 startTime, uint64 duration) internal virtual {}

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
    function getAmountIn(uint128 amountOut, uint64 currentTime) external view returns (uint256 amountIn) {
        Auction memory _auction = auction;
        uint256 currentPrice = _getCurrentPrice(_auction, currentTime);
        return _getAmountIn(amountOut, currentPrice);
    }

    /// @dev An internal helper function to get the amount of tokens to be paid by the filler
    /// @param amountOut The amount of tokens to be sold
    /// @param currentPrice The current price of the auction
    /// @return amountIn The amount of tokens to be paid by the filler
    function _getAmountIn(uint128 amountOut, uint256 currentPrice) internal pure returns (uint256 amountIn) {
        amountIn = (amountOut * currentPrice) / 10 ** decimals;
        return (amountIn == 0) ? 1 : amountIn;
    }

    /// @dev An internal helper function to get the current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken
    /// @param _auction The auction to get the current price from
    /// @param currentTime The time the filler is calling the function
    /// @return currentPrice The current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken
    function _getCurrentPrice(Auction memory _auction, uint256 currentTime)
        internal
        pure
        returns (uint256 currentPrice)
    {
        uint256 delta_p = _auction.startPrice - _auction.endPrice;
        uint256 delta_t = _auction.duration - (currentTime - _auction.startTime);
        currentPrice = ((delta_p * delta_t) / _auction.duration) + _auction.endPrice;
    }

    /// @notice An external helper function to get the current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken
    /// @param currentTime The time the filler is calling the function
    /// @return currentPrice The current price of the auction in decimals as a ratio of EthStrategy tokens to paymentToken
    function getCurrentPrice(uint256 currentTime) external view returns (uint256 currentPrice) {
        Auction memory _auction = auction;
        if (!_isAuctionActive(_auction, currentTime)) {
            revert AuctionNotActive();
        }
        currentPrice = _getCurrentPrice(_auction, currentTime);
    }

    /// @dev An external helper function to check if the auction is active
    /// @param currentTime The time the filler is calling the function
    /// @return bool true if the auction is active, false otherwise
    function isAuctionActive(uint256 currentTime) external view returns (bool) {
        Auction memory _auction = auction;
        return _isAuctionActive(_auction, currentTime);
    }

    /// @dev A modifier to check if the user is whitelisted (hasRedeemed is updated)
    /// @param signature The signature of the whitelist spot for the msg.sender
    modifier whitelist(bytes calldata signature) {
        if (signer != address(0)) {
            bytes32 key = keccak256(
                abi.encodePacked(auction.startTime, auction.duration, auction.startPrice, auction.endPrice, msg.sender)
            );
            if (hasRedeemed[key]) revert AlreadyRedeemed();
            hasRedeemed[key] = true;
            bytes32 hash = SignatureCheckerLib.toEthSignedMessageHash(abi.encodePacked(msg.sender));
            if (!SignatureCheckerLib.isValidSignatureNow(signer, hash, signature)) revert InvalidSignature();
        }
        _;
    }

    /// @notice set the signer
    /// @param _signer the new signer
    /// @dev only the owner can set the signer
    function setSigner(address _signer) external onlyOwnerOrRoles(DA_ADMIN_ROLE) {
        signer = _signer;
    }

    /// @dev A fallback function to reject any ETH sent to the contract that is not using a payable method
    receive() external payable {
        revert InvalidCall();
    }
}
