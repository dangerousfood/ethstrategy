// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {DutchAuctionTest} from "./DutchAuction.t.sol";
import {BondAuction} from "../src/BondAuction.sol";
import {DutchAuction} from "../src/DutchAuction.sol";

contract BondAuctionTest is DutchAuctionTest {
    function setUp() public override {
        super.setUp();
        vm.prank(admin1.addr);
        dutchAuction = new BondAuction(address(ethStrategy), address(usdcToken), address(0));
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        vm.stopPrank();
        vm.startPrank(address(ethStrategy));
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        vm.stopPrank();
    }

    function test_constructor_success() public {
        dutchAuction = new BondAuction(address(ethStrategy), address(usdcToken), address(0));
        assertEq(dutchAuction.ethStrategy(), address(ethStrategy), "ethStrategy not assigned correctly");
        assertEq(dutchAuction.paymentToken(), address(usdcToken), "paymentToken not assigned correctly");
        assertEq(dutchAuction.owner(), address(ethStrategy), "ethStrategy not assigned correctly");
    }

    function test_fill_success_1() public override {
        uint256 amountIn = calculateAmountIn(
            defaultAmount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        mintAndApprove(alice, amountIn, address(dutchAuction), address(usdcToken));
        super.test_fill_success_1();

        assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
        assertEq(usdcToken.balanceOf(address(dutchAuction)), amountIn, "usdcToken balance not assigned correctly");
        BondAuction bondAuction = BondAuction(payable(dutchAuction));
        (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
        assertEq(amountOut, defaultAmount, "amount not assigned correctly");
        assertEq(_amountIn, amountIn, "amount not assigned correctly");
        assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
    }

    function test_fill_success_2() public override {
        uint128 _amount = defaultAmount - 1;
        mintAndApprove(
            alice,
            _amount * defaultStartPrice / (10 ** ethStrategy.decimals()),
            address(dutchAuction),
            address(usdcToken)
        );
        super.test_fill_success_2();
        uint256 amountIn = calculateAmountIn(
            _amount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
        assertEq(usdcToken.balanceOf(address(dutchAuction)), amountIn, "usdcToken balance not assigned correctly");
        BondAuction bondAuction = BondAuction(payable(dutchAuction));
        (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
        assertEq(amountOut, _amount, "amount not assigned correctly");
        assertEq(amountIn, _amountIn, "price not assigned correctly");
        assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
    }

    function test_redeem_success() public {
        test_fill_success_1();
        BondAuction bondAuction = BondAuction(payable(dutchAuction));
        vm.warp(block.timestamp + defaultDuration + 1);
        vm.prank(alice);
        bondAuction.redeem();
        assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), defaultAmount, "ethStrategy balance not assigned correctly");
        assertEq(usdcToken.balanceOf(address(dutchAuction)), 0, "usdcToken balance not assigned correctly");
        assertEq(
            usdcToken.balanceOf(address(ethStrategy)),
            defaultAmount * defaultStartPrice / (10 ** ethStrategy.decimals()),
            "usdcToken balance not assigned correctly"
        );

        (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
        assertEq(amount, 0, "amount not assigned correctly");
        assertEq(price, 0, "price not assigned correctly");
        assertEq(startRedemption, 0, "startRedemption not assigned correctly");
    }

    function test_redeem_noBondToRedeem() public {
        test_fill_success_1();
        BondAuction bondAuction = BondAuction(payable(dutchAuction));
        vm.warp(block.timestamp + defaultDuration + 1);
        vm.expectRevert(BondAuction.NoBondToRedeem.selector);
        bondAuction.redeem();
    }

    function test_redeem_redemptionWindowNotStarted() public {
        test_fill_success_1();
        BondAuction bondAuction = BondAuction(payable(dutchAuction));
        vm.warp(block.timestamp + defaultDuration - 1);
        vm.prank(alice);
        vm.expectRevert(BondAuction.RedemptionWindowNotStarted.selector);
        bondAuction.redeem();
        uint256 amountIn = calculateAmountIn(
            defaultAmount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
        assertEq(amountOut, defaultAmount, "amount not assigned correctly");
        assertEq(amountIn, _amountIn, "price not assigned correctly");
        assertEq(startRedemption, block.timestamp + 1, "startRedemption not assigned correctly");
    }

    function test_redeem_redemptionWindowPassed() public {
        uint256 startTime = block.timestamp;
        test_fill_success_1();
        BondAuction bondAuction = BondAuction(payable(dutchAuction));
        vm.warp(startTime + defaultDuration + bondAuction.REDEMPTION_WINDOW() + 1);
        vm.prank(alice);
        vm.expectRevert(BondAuction.RedemptionWindowPassed.selector);
        bondAuction.redeem();
        uint256 amountIn = calculateAmountIn(
            defaultAmount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
        assertEq(amountOut, defaultAmount, "amount not assigned correctly");
        assertEq(amountIn, _amountIn, "price not assigned correctly");
        assertEq(startRedemption, startTime + defaultDuration, "startRedemption not assigned correctly");
    }

    function test_withdraw_success() public {
        test_fill_success_1();
        BondAuction bondAuction = BondAuction(payable(dutchAuction));
        vm.warp(block.timestamp + defaultDuration + 1);
        vm.prank(alice);
        bondAuction.withdraw();
        assertEq(
            usdcToken.balanceOf(alice),
            defaultAmount * defaultStartPrice / (10 ** ethStrategy.decimals()),
            "usdcToken balance not assigned correctly"
        );
        assertEq(usdcToken.balanceOf(address(dutchAuction)), 0, "usdcToken balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), 0, "ethStrategy balance not assigned correctly");

        (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
        assertEq(amount, 0, "amount not assigned correctly");
        assertEq(price, 0, "price not assigned correctly");
        assertEq(startRedemption, 0, "startRedemption not assigned correctly");
    }

    function test_withdraw_noBondToWithdraw() public {
        test_fill_success_1();
        BondAuction bondAuction = BondAuction(payable(dutchAuction));
        vm.warp(block.timestamp + defaultDuration + 1);
        vm.expectRevert(BondAuction.NoBondToWithdraw.selector);
        bondAuction.withdraw();
        uint256 amountIn = calculateAmountIn(
            defaultAmount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
        assertEq(amountOut, defaultAmount, "amount not assigned correctly");
        assertEq(_amountIn, amountIn, "price not assigned correctly");
        assertEq(startRedemption, block.timestamp - 1, "startRedemption not assigned correctly");
    }

    function test_withdraw_redemptionWindowNotStarted() public {
        test_fill_success_1();
        BondAuction bondAuction = BondAuction(payable(dutchAuction));
        vm.expectRevert(BondAuction.RedemptionWindowNotStarted.selector);
        vm.prank(alice);
        bondAuction.withdraw();
        uint256 amountIn = calculateAmountIn(
            defaultAmount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
        assertEq(amountOut, defaultAmount, "amount not assigned correctly");
        assertEq(amountIn, _amountIn, "price not assigned correctly");
        assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
    }

    function test_fill_unredeemedBond() public {
        uint64 expectedStartTime = uint64(block.timestamp);
        uint128 _amount = defaultAmount / 2;
        uint256 amountIn = calculateAmountIn(
            _amount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        mintAndApprove(alice, amountIn, address(dutchAuction), address(usdcToken));

        test_startAuction_success_1();
        vm.prank(alice);
        vm.expectEmit();
        emit DutchAuction.AuctionFilled(alice, _amount, amountIn);
        dutchAuction.fill(_amount, "");

        {
            (uint64 startTime, uint64 duration, uint128 amount, uint256 startPrice, uint256 endPrice) =
                dutchAuction.auction();
            assertEq(startTime, expectedStartTime, "startTime not assigned correctly");
            assertEq(duration, defaultDuration, "duration not assigned correctly");
            assertEq(startPrice, defaultStartPrice, "startPrice not assigned correctly");
            assertEq(endPrice, defaultEndPrice, "endPrice not assigned correctly");
            assertEq(amount, defaultAmount - _amount, "amount not assigned correctly");
        }

        assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
        assertEq(
            usdcToken.balanceOf(address(dutchAuction)),
            _amount * defaultStartPrice / (10 ** ethStrategy.decimals()),
            "usdcToken balance not assigned correctly"
        );
        BondAuction bondAuction = BondAuction(payable(dutchAuction));

        {
            (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
            assertEq(amount, _amount, "amount not assigned correctly");
            assertEq(price, amountIn, "price not assigned correctly");
            assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
        }

        mintAndApprove(alice, _amount * defaultStartPrice, address(dutchAuction), address(usdcToken));
        vm.prank(alice);
        vm.expectRevert(BondAuction.UnredeemedBond.selector);
        dutchAuction.fill(_amount, "");
    }

    function test_whitelist_example_signature() public virtual override {
        address filler = 0x2Fc9478c3858733b6e9b87458D71044A2071a300;
        mintAndApprove(filler, defaultAmount, address(dutchAuction), address(dutchAuction.paymentToken()));
        super.test_whitelist_example_signature();
    }

    function fill(
        uint128 _amount,
        uint64 _startTime,
        uint64 _duration,
        uint128 _startPrice,
        uint128 _endPrice,
        uint64 _elapsedTime,
        uint128 _totalAmount
    ) public virtual override {
        uint256 amountIn = calculateAmountIn(
            _amount, _startTime, _duration, _startPrice, _endPrice, _elapsedTime, dutchAuction.decimals()
        );
        mintAndApprove(alice, amountIn, address(dutchAuction), address(dutchAuction.paymentToken()));
        super.fill(_amount, _startTime, _duration, _startPrice, _endPrice, _elapsedTime, _totalAmount);
        assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
        assertEq(usdcToken.balanceOf(address(dutchAuction)), amountIn, "usdcToken balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), 0, "ethStrategy balance not assigned correctly");
    }
}
