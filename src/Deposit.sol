// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./EthStrategy.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {TReentrancyGuard} from "../lib/TReentrancyGuard/src/TReentrancyGuard.sol";

contract Deposit is Ownable, TReentrancyGuard {
    /// @dev The conversion rate from ETH to EthStrategy (unit accounts)
    uint256 public immutable CONVERSION_RATE;
    /// @dev The minimum amount of ETH that can be deposited
    uint256 constant MIN_DEPOSIT = 1e18;
    /// @dev The maximum amount of ETH that can be deposited
    uint256 constant MAX_DEPOSIT = 100e18;

    error DepositAmountTooLow();
    error DepositAmountTooHigh();
    error DepositFailed();
    error AlreadyRedeemed();
    error DepositCapExceeded();
    error InvalidConversionPremium();
    error InvalidSignature();
    error InvalidCall();
    error DepositNotStarted();

    /// @dev The address of the Ethstrategy token
    address public immutable ethStrategy;
    /// @dev The address of the signer (if signer is set, whitelist is enabled)
    address public signer;
    /// @dev A mapping to track if a user has redeemed whitelist spot
    mapping(address => bool) public hasRedeemed;

    uint256 public immutable conversionPremium;
    uint64 public immutable startTime;
    uint256 public constant DENOMINATOR_BP = 100_00;
    /// @dev The maximum amount of ETH that can be deposited
    uint256 private depositCap_;

    /// @notice constructor
    /// @param _ethStrategy the address of the ethstrategy token
    /// @param _signer the address of the signer (if signer is set, whitelist is enabled)
    /// @param _conversionRate the conversion rate from eth to ethstrategy
    /// @param _conversionPremium the conversion premium in basis points (0 - 100_00)
    /// @param _depositCap the maximum global deposit cap
    constructor(
        address _ethStrategy,
        address _signer,
        uint256 _conversionRate,
        uint256 _conversionPremium,
        uint256 _depositCap,
        uint64 _startTime
    ) {
        if (_conversionPremium > DENOMINATOR_BP) revert InvalidConversionPremium();
        CONVERSION_RATE = _conversionRate;
        _initializeOwner(_ethStrategy);
        ethStrategy = _ethStrategy;
        signer = _signer;
        conversionPremium = _conversionPremium;
        depositCap_ = _depositCap;
        startTime = _startTime;
    }
    /// @notice deposit eth and mint ethstrategy
    /// @param signature the signature of the signer for the depositor

    function deposit(bytes calldata signature) external payable nonreentrant {
        if (block.timestamp < startTime) revert DepositNotStarted();
        uint256 value = msg.value;
        uint256 _depositCap = depositCap_;
        if (value > _depositCap) revert DepositCapExceeded();
        depositCap_ = _depositCap - value;

        if (signer != address(0)) {
            if (hasRedeemed[msg.sender]) revert AlreadyRedeemed();
            hasRedeemed[msg.sender] = true;
            bytes32 hash = SignatureCheckerLib.toEthSignedMessageHash(abi.encodePacked(msg.sender));
            if (!SignatureCheckerLib.isValidSignatureNow(signer, hash, signature)) revert InvalidSignature();
        }

        if (value < MIN_DEPOSIT) revert DepositAmountTooLow();
        if (value > MAX_DEPOSIT) revert DepositAmountTooHigh();

        uint256 amount = msg.value * CONVERSION_RATE;
        amount = amount * (DENOMINATOR_BP - conversionPremium) / DENOMINATOR_BP;

        IEthStrategy(ethStrategy).mint(msg.sender, amount);

        address payable recipient = payable(owner());
        (bool success,) = recipient.call{value: msg.value}("");
        if (!success) revert DepositFailed();
    }
    /// @notice get the current deposit cap
    /// @return the current deposit cap

    function depositCap() external view returns (uint256) {
        return depositCap_;
    }
    /// @notice set the signer
    /// @param _signer the new signer
    /// @dev only the owner can set the signer

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }
    /// @dev A fallback function to reject any ETH sent to the contract that is not using a payable method

    receive() external payable {
        revert InvalidCall();
    }
}
