// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {BondAuctionTest} from "./BondAuction.t.sol";
import {BondAuction} from "../src/BondAuction.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {IEthStrategy} from "../src/EthStrategy.sol";

/**
 * @title BondAuctionFuzz
 * @notice Fuzzing and property-based tests for the BondAuction contract
 * @dev Extends BondAuctionTest to leverage existing setup
 */
contract BondAuctionFuzz is BondAuctionTest {
    BondAuction bondAuction;

    function setUp() public override {
        super.setUp();
        bondAuction = BondAuction(address(dutchAuction));
    }

    /**
     * @notice Test the getBondState function with fuzzed inputs
     * @param user Address to check bond state for
     * @param startRedemptionOffset Time offset for startRedemption
     * @param timeWarp Time to warp to
     */
    function testFuzz_getBondState_Properties(
        address user,
        uint64 startRedemptionOffset,
        uint64 timeWarp
    ) public {
        vm.assume(user != address(0));
        vm.assume(user != alice); // Avoid conflicts with existing bonds
        vm.assume(startRedemptionOffset > 0);
        vm.assume(timeWarp > 0);
        
        // Property 1: If no bond exists, state should be None
        assertEq(uint(bondAuction.getBondState(user)), uint(BondAuction.BondState.None), "State should be None for non-existent bond");
        
        // Create a bond for the user
        uint64 currentTime = uint64(block.timestamp);
        uint64 startRedemption = currentTime + startRedemptionOffset;
        
        // Directly set a bond for the user (bypassing _fill to isolate testing getBondState)
        vm.startPrank(address(bondAuction));
        bondAuction.bonds(user);
        vm.stopPrank();
        
        // Create a bond through the normal flow
        test_startAuction_success_1();
        uint128 amountOut = defaultAmount / 2;
        uint128 amountIn = calculateAmountIn(
            amountOut,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        
        mintAndApprove(user, amountIn, address(bondAuction), address(usdcToken));
        vm.prank(user);
        bondAuction.fill(amountOut);
        
        // Get the actual startRedemption from the created bond
        (,, uint64 actualStartRedemption) = bondAuction.bonds(user);
        
        // Property 2: If current time < startRedemption, state should be Pending
        vm.warp(actualStartRedemption - 1);
        assertEq(uint(bondAuction.getBondState(user)), uint(BondAuction.BondState.Pending), "State should be Pending before redemption window");
        
        // Property 3: If startRedemption ≤ current time ≤ startRedemption + REDEMPTION_WINDOW, state should be Redeemable
        vm.warp(actualStartRedemption);
        assertEq(uint(bondAuction.getBondState(user)), uint(BondAuction.BondState.Redeemable), "State should be Redeemable at start of window");
        
        vm.warp(actualStartRedemption + bondAuction.REDEMPTION_WINDOW());
        assertEq(uint(bondAuction.getBondState(user)), uint(BondAuction.BondState.Redeemable), "State should be Redeemable at end of window");
        
        // Property 4: If current time > startRedemption + REDEMPTION_WINDOW, state should be Expired
        vm.warp(actualStartRedemption + bondAuction.REDEMPTION_WINDOW() + 1);
        assertEq(uint(bondAuction.getBondState(user)), uint(BondAuction.BondState.Expired), "State should be Expired after redemption window");
    }

    /**
     * @notice Test state transitions with fuzzed time offsets
     * @param timeOffset Time offset to test different state transitions
     */
    function testFuzz_BondStateTransitions(uint64 timeOffset) public {
        vm.assume(timeOffset > 0 && timeOffset < 30 days);
        
        // Setup
        test_startAuction_success_1();
        uint128 amountOut = defaultAmount / 2;
        uint128 amountIn = calculateAmountIn(
            amountOut,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        
        mintAndApprove(alice, amountIn, address(bondAuction), address(usdcToken));
        
        // Initial state: None
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.None), "Initial state should be None");
        
        // Create bond
        vm.prank(alice);
        bondAuction.fill(amountOut);
        
        // Get the actual startRedemption from the created bond
        (,, uint64 startRedemption) = bondAuction.bonds(alice);
        
        // State after creation: Pending
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Pending), "State after creation should be Pending");
        
        // Warp to redemption window start
        vm.warp(startRedemption);
        
        // State at redemption window start: Redeemable
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Redeemable), "State at redemption start should be Redeemable");
        
        // Warp to redemption window end
        vm.warp(startRedemption + bondAuction.REDEMPTION_WINDOW());
        
        // State at redemption window end: Redeemable
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Redeemable), "State at redemption end should be Redeemable");
        
        // Warp past redemption window
        vm.warp(startRedemption + bondAuction.REDEMPTION_WINDOW() + timeOffset);
        
        // State after redemption window: Expired
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Expired), "State after redemption window should be Expired");
    }

    /**
     * @notice Test the redeem function with fuzzed parameters
     * @param amountOut Amount of tokens to be received
     * @param timeOffset Time offset for testing different redemption scenarios
     */
    function testFuzz_redeem(uint128 amountOut, uint64 timeOffset) public {
        // Bound inputs to reasonable values
        vm.assume(amountOut > 0 && amountOut <= defaultAmount);
        vm.assume(timeOffset > 0 && timeOffset < bondAuction.REDEMPTION_WINDOW());
        
        // Setup
        test_startAuction_success_1();
        uint128 amountIn = calculateAmountIn(
            amountOut,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        
        mintAndApprove(alice, amountIn, address(bondAuction), address(usdcToken));
        
        // Create bond
        vm.prank(alice);
        bondAuction.fill(amountOut);
        
        // Get the actual startRedemption from the created bond
        (uint128 bondAmountOut, uint128 bondAmountIn, uint64 startRedemption) = bondAuction.bonds(alice);
        
        // Verify bond was created correctly
        assertEq(bondAmountOut, amountOut, "Bond amountOut incorrect");
        assertEq(bondAmountIn, amountIn, "Bond amountIn incorrect");
        
        // Warp to redemption window
        vm.warp(startRedemption + timeOffset);
        
        // Verify state is Redeemable
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Redeemable), "State should be Redeemable");
        
        // Record balances before redemption
        uint256 aliceEthStrategyBefore = ethStrategy.balanceOf(alice);
        uint256 ownerUsdcBefore = usdcToken.balanceOf(address(ethStrategy));
        
        // Redeem bond
        vm.prank(alice);
        bondAuction.redeem();
        
        // Verify bond was deleted
        (uint128 newAmountOut, uint128 newAmountIn, uint64 newStartRedemption) = bondAuction.bonds(alice);
        assertEq(newStartRedemption, 0, "Bond should be deleted after redemption");
        
        // Verify tokens were transferred correctly
        assertEq(ethStrategy.balanceOf(alice) - aliceEthStrategyBefore, amountOut, "EthStrategy tokens not transferred correctly");
        assertEq(usdcToken.balanceOf(address(ethStrategy)) - ownerUsdcBefore, amountIn, "USDC tokens not transferred correctly");
        
        // Verify state is now None
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.None), "State should be None after redemption");
    }

    /**
     * @notice Test the withdraw function with fuzzed parameters
     * @param amountOut Amount of tokens to be received
     * @param timeOffset Time offset for testing different withdrawal scenarios
     * @param afterRedemptionWindow Whether to test withdrawal after the redemption window
     */
    function testFuzz_withdraw(
        uint128 amountOut,
        uint64 timeOffset,
        bool afterRedemptionWindow
    ) public {
        // Bound inputs to reasonable values
        vm.assume(amountOut > 0 && amountOut <= defaultAmount);
        vm.assume(timeOffset > 0 && timeOffset < 30 days);
        
        // Setup
        test_startAuction_success_1();
        uint128 amountIn = calculateAmountIn(
            amountOut,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        
        mintAndApprove(alice, amountIn, address(bondAuction), address(usdcToken));
        
        // Create bond
        vm.prank(alice);
        bondAuction.fill(amountOut);
        
        // Get the actual startRedemption from the created bond
        (uint128 bondAmountOut, uint128 bondAmountIn, uint64 startRedemption) = bondAuction.bonds(alice);
        
        // Verify bond was created correctly
        assertEq(bondAmountOut, amountOut, "Bond amountOut incorrect");
        assertEq(bondAmountIn, amountIn, "Bond amountIn incorrect");
        
        // Warp to appropriate time
        if (afterRedemptionWindow) {
            vm.warp(startRedemption + bondAuction.REDEMPTION_WINDOW() + timeOffset);
            // Verify state is Expired
            assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Expired), "State should be Expired");
        } else {
            vm.warp(startRedemption + timeOffset % bondAuction.REDEMPTION_WINDOW());
            // Verify state is Redeemable
            assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Redeemable), "State should be Redeemable");
        }
        
        // Record balances before withdrawal
        uint256 aliceUsdcBefore = usdcToken.balanceOf(alice);
        
        // Withdraw bond
        vm.prank(alice);
        bondAuction.withdraw();
        
        // Verify bond was deleted
        (uint128 newAmountOut, uint128 newAmountIn, uint64 newStartRedemption) = bondAuction.bonds(alice);
        assertEq(newStartRedemption, 0, "Bond should be deleted after withdrawal");
        
        // Verify tokens were transferred correctly
        assertEq(usdcToken.balanceOf(alice) - aliceUsdcBefore, amountIn, "USDC tokens not transferred correctly");
        
        // Verify state is now None
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.None), "State should be None after withdrawal");
    }

    /**
     * @notice Test edge cases for redemption and withdrawal
     * @param amountOut Amount of tokens to be received
     */
    function testFuzz_EdgeCases(uint128 amountOut) public {
        // Bound inputs to reasonable values
        vm.assume(amountOut > 0 && amountOut <= defaultAmount);
        
        // Setup
        test_startAuction_success_1();
        uint128 amountIn = calculateAmountIn(
            amountOut,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        
        mintAndApprove(alice, amountIn, address(bondAuction), address(usdcToken));
        
        // Create bond
        vm.prank(alice);
        bondAuction.fill(amountOut);
        
        // Get the actual startRedemption from the created bond
        (,, uint64 startRedemption) = bondAuction.bonds(alice);
        
        // Edge case 1: Redemption exactly at startRedemption
        vm.warp(startRedemption);
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Redeemable), "State should be Redeemable at exact start");
        
        // Edge case 2: Redemption exactly at startRedemption + REDEMPTION_WINDOW
        vm.warp(startRedemption + bondAuction.REDEMPTION_WINDOW());
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Redeemable), "State should be Redeemable at exact end");
        
        // Edge case 3: Redemption one second after window ends
        vm.warp(startRedemption + bondAuction.REDEMPTION_WINDOW() + 1);
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Expired), "State should be Expired one second after window");
        
        // Edge case 4: Withdrawal at exact start of redemption window
        // First create a new bond for bob
        mintAndApprove(bob, amountIn, address(bondAuction), address(usdcToken));
        vm.prank(bob);
        bondAuction.fill(amountOut);
        
        (,, uint64 bobStartRedemption) = bondAuction.bonds(bob);
        vm.warp(bobStartRedemption);
        
        // Withdraw at exact start of redemption window
        vm.prank(bob);
        bondAuction.withdraw();
        
        // Verify bond was deleted
        (,, uint64 newBobStartRedemption) = bondAuction.bonds(bob);
        assertEq(newBobStartRedemption, 0, "Bond should be deleted after withdrawal at exact start");
    }

    /**
     * @notice Test invariant: After successful redeem or withdraw, bond should be deleted
     */
    function testInvariant_BondDeletion() public {
        // Setup for redeem
        test_startAuction_success_1();
        uint128 amountOut = defaultAmount / 2;
        uint128 amountIn = calculateAmountIn(
            amountOut,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        
        // Create bonds for alice and bob
        mintAndApprove(alice, amountIn, address(bondAuction), address(usdcToken));
        mintAndApprove(bob, amountIn, address(bondAuction), address(usdcToken));
        
        vm.prank(alice);
        bondAuction.fill(amountOut);
        
        vm.prank(bob);
        bondAuction.fill(amountOut);
        
        // Get startRedemption times
        (,, uint64 aliceStartRedemption) = bondAuction.bonds(alice);
        (,, uint64 bobStartRedemption) = bondAuction.bonds(bob);
        
        // Warp to redemption window
        vm.warp(aliceStartRedemption + 1);
        
        // Alice redeems
        vm.prank(alice);
        bondAuction.redeem();
        
        // Bob withdraws
        vm.prank(bob);
        bondAuction.withdraw();
        
        // Verify bonds are deleted
        (,, uint64 newAliceStartRedemption) = bondAuction.bonds(alice);
        (,, uint64 newBobStartRedemption) = bondAuction.bonds(bob);
        
        assertEq(newAliceStartRedemption, 0, "Alice's bond should be deleted after redemption");
        assertEq(newBobStartRedemption, 0, "Bob's bond should be deleted after withdrawal");
    }

    /**
     * @notice Test invariant: Token transfers should be correct after redeem and withdraw
     */
    function testInvariant_TokenTransfers() public {
        // Setup
        test_startAuction_success_1();
        uint128 amountOut = defaultAmount / 2;
        uint128 amountIn = calculateAmountIn(
            amountOut,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        
        // Create bonds for alice and bob
        mintAndApprove(alice, amountIn, address(bondAuction), address(usdcToken));
        mintAndApprove(bob, amountIn, address(bondAuction), address(usdcToken));
        
        vm.prank(alice);
        bondAuction.fill(amountOut);
        
        vm.prank(bob);
        bondAuction.fill(amountOut);
        
        // Get startRedemption times
        (,, uint64 aliceStartRedemption) = bondAuction.bonds(alice);
        
        // Warp to redemption window
        vm.warp(aliceStartRedemption + 1);
        
        // Record balances before operations
        uint256 aliceEthStrategyBefore = ethStrategy.balanceOf(alice);
        uint256 bobUsdcBefore = usdcToken.balanceOf(bob);
        uint256 ownerUsdcBefore = usdcToken.balanceOf(address(ethStrategy));
        
        // Alice redeems
        vm.prank(alice);
        bondAuction.redeem();
        
        // Bob withdraws
        vm.prank(bob);
        bondAuction.withdraw();
        
        // Verify token transfers
        assertEq(ethStrategy.balanceOf(alice) - aliceEthStrategyBefore, amountOut, "Alice should receive correct EthStrategy tokens");
        assertEq(usdcToken.balanceOf(bob) - bobUsdcBefore, amountIn, "Bob should receive correct USDC tokens");
        assertEq(usdcToken.balanceOf(address(ethStrategy)) - ownerUsdcBefore, amountIn, "Owner should receive correct USDC tokens");
    }

    /**
     * @notice Test invariant: Bond state should be consistent with timestamps
     */
    function testInvariant_StateConsistency() public {
        // Setup
        test_startAuction_success_1();
        uint128 amountOut = defaultAmount / 2;
        uint128 amountIn = calculateAmountIn(
            amountOut,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        
        // Create bond
        mintAndApprove(alice, amountIn, address(bondAuction), address(usdcToken));
        vm.prank(alice);
        bondAuction.fill(amountOut);
        
        // Get startRedemption time
        (,, uint64 startRedemption) = bondAuction.bonds(alice);
        
        // Test state consistency at different times
        
        // Before redemption window
        vm.warp(startRedemption - 1);
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Pending), "State should be Pending before window");
        
        // At start of redemption window
        vm.warp(startRedemption);
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Redeemable), "State should be Redeemable at start");
        
        // During redemption window
        vm.warp(startRedemption + bondAuction.REDEMPTION_WINDOW() / 2);
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Redeemable), "State should be Redeemable during window");
        
        // At end of redemption window
        vm.warp(startRedemption + bondAuction.REDEMPTION_WINDOW());
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Redeemable), "State should be Redeemable at end");
        
        // After redemption window
        vm.warp(startRedemption + bondAuction.REDEMPTION_WINDOW() + 1);
        assertEq(uint(bondAuction.getBondState(alice)), uint(BondAuction.BondState.Expired), "State should be Expired after window");
    }

    /**
     * @notice Test that events are properly emitted
     * @param amountOut Amount of tokens to be received
     */
    function testFuzz_EventEmission(uint128 amountOut) public {
        // Bound inputs to reasonable values
        vm.assume(amountOut > 0 && amountOut <= defaultAmount);
        
        // Setup
        test_startAuction_success_1();
        uint128 amountIn = calculateAmountIn(
            amountOut,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        
        mintAndApprove(alice, amountIn, address(bondAuction), address(usdcToken));
        
        // Test BondCreated event
        vm.expectEmit(true, false, false, true);
        emit BondAuction.BondCreated(alice, amountOut, amountIn, uint64(block.timestamp) + defaultDuration);
        
        vm.prank(alice);
        bondAuction.fill(amountOut);
        
        // Get startRedemption time
        (,, uint64 startRedemption) = bondAuction.bonds(alice);
        
        // Warp to redemption window
        vm.warp(startRedemption + 1);
        
        // Test BondRedeemed event
        vm.expectEmit(true, false, false, true);
        emit BondAuction.BondRedeemed(alice, amountOut, amountIn);
        
        vm.prank(alice);
        bondAuction.redeem();
        
        // Create another bond for testing withdrawal
        mintAndApprove(bob, amountIn, address(bondAuction), address(usdcToken));
        
        vm.prank(bob);
        bondAuction.fill(amountOut);
        
        // Get startRedemption time
        (,, uint64 bobStartRedemption) = bondAuction.bonds(bob);
        
        // Warp to redemption window
        vm.warp(bobStartRedemption + 1);
        
        // Test BondWithdrawn event
        vm.expectEmit(true, false, false, true);
        emit BondAuction.BondWithdrawn(bob, amountIn);
        
        vm.prank(bob);
        bondAuction.withdraw();
    }
}
