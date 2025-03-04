// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {DutchAuction} from "./DutchAuction.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./interfaces/IEthStrategy.sol";

contract BondAuction is DutchAuction {
    /// @dev The struct for the bond parameters
    struct Bond {
        uint128 amountOut;
        uint256 amountIn;
        uint64 startRedemption;
    }

    error UnredeemedBond();
    error NoBondToRedeem();
    error RedemptionWindowNotStarted();
    error RedemptionWindowPassed();
    error NoBondToWithdraw();

    /// @notice A mapping to track the bonds for each address
    mapping(address => Bond) public bonds;
    /// @notice The redemption window for the bonds (in seconds)
    uint256 public constant REDEMPTION_WINDOW = 1 days;

    /// @dev The constructor for the BondAuction contract, initializes the DutchAuction contract
    /// @param _ethStrategy The address of the EthStrategy contract
    /// @param _paymentToken The address of the payment token
    constructor(address _ethStrategy, address _paymentToken, address _signer)
        DutchAuction(_ethStrategy, _paymentToken, _signer)
    {}
    /// @dev An internal override of the _fill function from DutchAuction, transfers the paymentToken to the contract and creates a bond for the filler
    /// @param amountOut The amount of tokens to be sold (in the future during the strike window)
    /// @param amountIn The amount of tokens to be paid by the filler
    /// @param startTime The start time of the auction
    /// @param duration The duration of the auction

    function _fill(uint128 amountOut, uint256 amountIn, uint64 startTime, uint64 duration) internal override {
        if (bonds[msg.sender].startRedemption != 0) {
            revert UnredeemedBond();
        }
        SafeTransferLib.safeTransferFrom(paymentToken, msg.sender, address(this), amountIn);
        bonds[msg.sender] = Bond({amountOut: amountOut, amountIn: amountIn, startRedemption: startTime + duration});
    }
    /// @notice An external function to redeem a bond, can only be called by the filler

    function redeem() external {
        _redeem();
    }
    /// @dev An internal function to be called when the redeemer redeems a bond, checks if the redemption window has started and if it has passed, then transfers the paymentToken from the redeemer to the owner() and mints the EthStrategy tokens to the redeemer

    function _redeem() internal {
        Bond memory bond = bonds[msg.sender];
        if (bond.startRedemption == 0) {
            revert NoBondToRedeem();
        }
        uint256 currentTime = block.timestamp;
        if (currentTime < bond.startRedemption) {
            revert RedemptionWindowNotStarted();
        }
        if (currentTime > bond.startRedemption + REDEMPTION_WINDOW) {
            revert RedemptionWindowPassed();
        }
        delete bonds[msg.sender];
        SafeTransferLib.safeTransfer(paymentToken, owner(), bond.amountIn);
        IEthStrategy(ethStrategy).mint(msg.sender, bond.amountOut);
    }
    /// @notice An external function to withdraw a bond, can only be called by the filler

    function withdraw() external {
        _withdraw();
    }
    /// @dev An internal function to be called when the withdrawer withdraws a bond, checks if the redemption window has started and if it has passed, then transfers the paymentToken to the withdrawer and deletes the bond

    function _withdraw() internal {
        Bond memory bond = bonds[msg.sender];
        if (bond.startRedemption == 0) {
            revert NoBondToWithdraw();
        }
        uint256 currentTime = block.timestamp;
        if (currentTime < bond.startRedemption) {
            revert RedemptionWindowNotStarted();
        }
        SafeTransferLib.safeTransfer(paymentToken, msg.sender, bond.amountIn);
        delete bonds[msg.sender];
    }
}
