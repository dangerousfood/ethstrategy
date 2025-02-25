// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {DutchAuction} from "./DutchAuction.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./EthStrategy.sol";

/**
 * @title BondAuction
 * @notice A contract that extends DutchAuction to implement a bond mechanism
 * @dev Users can purchase bonds during a Dutch auction and later redeem them for EthStrategy tokens
 *      or withdraw their payment tokens. Bonds have a specific lifecycle with explicit states.
 */
contract BondAuction is DutchAuction {
    /**
     * @notice Enum representing the possible states of a bond
     * @dev This makes the bond lifecycle explicit and easier to reason about
     * @param None No bond exists for the user
     * @param Pending Bond exists but redemption window hasn't started yet
     * @param Redeemable Bond is within the redemption window and can be redeemed or withdrawn
     * @param Expired Bond's redemption window has passed, can only be withdrawn
     */
    enum BondState {
        None,
        Pending,
        Redeemable,
        Expired
    }

    /**
     * @notice The struct for the bond parameters
     * @dev The struct now includes an explicit state field for better state tracking
     * @param amountOut The amount of EthStrategy tokens to be received upon redemption
     * @param amountIn The amount of payment tokens paid for the bond
     * @param startRedemption The timestamp when the redemption window starts
     */
    struct Bond {
        uint128 amountOut;
        uint128 amountIn;
        uint64 startRedemption;
    }

    // Custom errors for better gas efficiency and clarity
    error UnredeemedBond();
    error NoBondToRedeem();
    error RedemptionWindowNotStarted();
    error RedemptionWindowPassed();
    error NoBondToWithdraw();
    error InvalidBondState();

    // Events for bond lifecycle tracking
    event BondCreated(address indexed user, uint128 amountOut, uint128 amountIn, uint64 startRedemption);
    event BondRedeemed(address indexed user, uint128 amountOut, uint128 amountIn);
    event BondWithdrawn(address indexed user, uint128 amountIn);

    /// @notice A mapping to track the bonds for each address
    mapping(address => Bond) public bonds;
    
    /// @notice The redemption window for the bonds (in seconds)
    /// @dev This is a fixed time window during which bonds can be redeemed
    uint256 public constant REDEMPTION_WINDOW = 1 days;

    /**
     * @notice Constructor for the BondAuction contract
     * @dev Initializes the DutchAuction contract with the provided parameters
     * @param _ethStrategy The address of the EthStrategy contract
     * @param _paymentToken The address of the payment token
     */
    constructor(address _ethStrategy, address _paymentToken) DutchAuction(_ethStrategy, _paymentToken) {}

    /**
     * @notice Get the current state of a bond for a given user
     * @dev This function determines the bond state based on timestamps and existence
     * @param user The address of the user whose bond state to check
     * @return state The current state of the user's bond
     */
    function getBondState(address user) public view returns (BondState) {
        Bond memory bond = bonds[user];
        
        // If startRedemption is 0, no bond exists
        if (bond.startRedemption == 0) {
            return BondState.None;
        }
        
        uint256 currentTime = block.timestamp;
        
        // If current time is before startRedemption, bond is pending
        if (currentTime < bond.startRedemption) {
            return BondState.Pending;
        }
        
        // If current time is within the redemption window, bond is redeemable
        if (currentTime <= bond.startRedemption + REDEMPTION_WINDOW) {
            return BondState.Redeemable;
        }
        
        // If current time is after the redemption window, bond is expired
        return BondState.Expired;
    }

    /**
     * @dev An internal override of the _fill function from DutchAuction
     * @dev Creates a bond for the filler after transferring payment tokens
     * @param amountOut The amount of tokens to be sold (in the future during the redemption window)
     * @param amountIn The amount of tokens to be paid by the filler
     * @param startTime The start time of the auction
     * @param duration The duration of the auction
     */
    function _fill(uint128 amountOut, uint128 amountIn, uint64 startTime, uint64 duration) internal override {
        // Ensure user doesn't already have an unredeemed bond
        // Invariant: A user can only have one bond at a time
        if (bonds[msg.sender].startRedemption != 0) {
            revert UnredeemedBond();
        }
        
        // Assumption: amountOut and amountIn are non-zero (validated in parent contract)
        
        // Transfer payment tokens from user to this contract
        // This happens before state changes, which is good for security
        SafeTransferLib.safeTransferFrom(paymentToken, msg.sender, address(this), amountIn);
        
        // Calculate redemption start time
        // Assumption: startTime + duration doesn't overflow (should be validated in parent contract)
        uint64 redemptionStart = startTime + duration;
        
        // Create a new bond for the user
        bonds[msg.sender] = Bond({
            amountOut: amountOut,
            amountIn: amountIn,
            startRedemption: redemptionStart
        });
        
        // Emit event for bond creation
        emit BondCreated(msg.sender, amountOut, amountIn, redemptionStart);
    }

    /**
     * @notice External function to redeem a bond
     * @dev Can only be called by the bond owner during the redemption window
     */
    function redeem() external nonreentrant {
        _redeem();
    }

    /**
     * @dev Internal function to redeem a bond
     * @dev Transfers payment tokens to owner and mints EthStrategy tokens to redeemer
     * @dev Can only be called during the redemption window
     */
    function _redeem() internal {
        // Get the bond and its current state
        Bond memory bond = bonds[msg.sender];
        BondState state = getBondState(msg.sender);
        
        // Validate bond state
        if (state == BondState.None) {
            revert NoBondToRedeem();
        }
        if (state == BondState.Pending) {
            revert RedemptionWindowNotStarted();
        }
        if (state == BondState.Expired) {
            revert RedemptionWindowPassed();
        }
        
        // Bond must be in Redeemable state at this point
        // Store values locally before state changes
        uint128 amountOut = bond.amountOut;
        uint128 amountIn = bond.amountIn;
        
        // Update state first (checks-effects-interactions pattern)
        delete bonds[msg.sender];
        
        // Then make external calls
        // Invariant: Payment tokens are transferred to the owner
        SafeTransferLib.safeTransfer(paymentToken, owner(), amountIn);
        
        // Invariant: EthStrategy tokens are minted to the redeemer
        IEthStrategy(ethStrategy).mint(msg.sender, amountOut);
        
        // Emit event for bond redemption
        emit BondRedeemed(msg.sender, amountOut, amountIn);
    }

    /**
     * @notice External function to withdraw a bond
     * @dev Can be called by the bond owner after the redemption window has started
     */
    function withdraw() external nonreentrant {
        _withdraw();
    }

    /**
     * @dev Internal function to withdraw a bond
     * @dev Returns payment tokens to the withdrawer
     * @dev Can be called after the redemption window has started (either during or after)
     */
    function _withdraw() internal {
        // Get the bond and its current state
        Bond memory bond = bonds[msg.sender];
        BondState state = getBondState(msg.sender);
        
        // Validate bond state
        if (state == BondState.None) {
            revert NoBondToWithdraw();
        }
        if (state == BondState.Pending) {
            revert RedemptionWindowNotStarted();
        }
        
        // Bond must be in Redeemable or Expired state at this point
        // Store values locally before state changes
        uint128 amountIn = bond.amountIn;
        
        // Update state first (checks-effects-interactions pattern)
        delete bonds[msg.sender];
        
        // Then make external calls
        // Invariant: Payment tokens are returned to the withdrawer
        SafeTransferLib.safeTransfer(paymentToken, msg.sender, amountIn);
        
        // Emit event for bond withdrawal
        emit BondWithdrawn(msg.sender, amountIn);
    }
}
