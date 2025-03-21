// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {DutchAuctionTest} from "./DutchAuction.t.sol";
import {AtmAuction} from "../src/AtmAuction.sol";
import {DutchAuction} from "../src/DutchAuction.sol";

contract AtmAuctionTest is DutchAuctionTest {
    function setUp() public override {
        super.setUp();
        vm.prank(admin1.addr);
        dutchAuction = new AtmAuction(address(ethStrategy), address(usdcToken), address(0));
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        vm.startPrank(address(ethStrategy));
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        vm.stopPrank();
    }

    function test_constructor_success() public {
        dutchAuction = new AtmAuction(address(ethStrategy), address(usdcToken), address(0));
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
        assertEq(
            usdcToken.balanceOf(address(ethStrategy)),
            defaultAmount * defaultStartPrice / (10 ** ethStrategy.decimals()),
            "usdcToken balance not assigned correctly"
        );
        assertEq(ethStrategy.balanceOf(alice), defaultAmount, "ethStrategy balance not assigned correctly");
    }

    function test_fill_success_2() public override {
        uint256 _amount = defaultAmount - 1;
        mintAndApprove(
            alice,
            _amount * defaultStartPrice / (10 ** ethStrategy.decimals()),
            address(dutchAuction),
            address(usdcToken)
        );
        super.test_fill_success_2();

        assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
        assertEq(
            usdcToken.balanceOf(address(ethStrategy)),
            _amount * defaultStartPrice / (10 ** ethStrategy.decimals()),
            "usdcToken balance not assigned correctly"
        );
        assertEq(ethStrategy.balanceOf(alice), _amount, "ethStrategy balance not assigned correctly");
    }

    function test_fill_revert_AmountInValueTooLow() public {
        vm.prank(admin1.addr);
        dutchAuction = new AtmAuction(address(ethStrategy), address(0), address(0));
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        vm.startPrank(address(ethStrategy));
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        vm.stopPrank();

        test_startAuction_success_1();
        uint256 amountIn = calculateAmountIn(
            defaultAmount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        vm.prank(alice);
        vm.deal(alice, amountIn - 1);
        vm.expectRevert(AtmAuction.AmountInValueTooLow.selector);
        dutchAuction.fill{value: amountIn - 1}(defaultAmount, "");
    }

    function test_fill_success_3() public {
        vm.prank(admin1.addr);
        dutchAuction = new AtmAuction(address(ethStrategy), address(0), address(0));
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        vm.startPrank(address(ethStrategy));
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        vm.stopPrank();

        test_startAuction_success_1();
        uint256 amountIn = calculateAmountIn(
            defaultAmount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        vm.deal(alice, amountIn);
        vm.prank(alice);
        vm.expectEmit();
        emit DutchAuction.AuctionEndedEarly();
        vm.expectEmit();
        emit DutchAuction.AuctionFilled(alice, defaultAmount, amountIn);
        dutchAuction.fill{value: amountIn}(defaultAmount, "");
        assertEq(alice.balance, 0, "alice balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), defaultAmount, "ethStrategy balance not assigned correctly");
        assertEq(address(ethStrategy).balance, amountIn, "ethStrategy balance not assigned correctly");
        (uint64 startTime, uint64 duration, uint128 amount, uint256 startPrice, uint256 endPrice) =
            dutchAuction.auction();
        assertEq(startTime, uint64(0), "startTime not assigned correctly");
        assertEq(duration, 0, "duration not assigned correctly");
        assertEq(startPrice, 0, "startPrice not assigned correctly");
        assertEq(endPrice, 0, "endPrice not assigned correctly");
        assertEq(amount, 0, "amount not assigned correctly");
    }

    function test_fill_success_4() public {
        vm.prank(admin1.addr);
        dutchAuction = new AtmAuction(address(ethStrategy), address(0), address(0));
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        vm.startPrank(address(ethStrategy));
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        vm.stopPrank();

        test_startAuction_success_1();
        uint256 amountIn = calculateAmountIn(
            defaultAmount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        vm.deal(alice, amountIn + 1);
        vm.prank(alice);
        vm.expectEmit();
        emit DutchAuction.AuctionEndedEarly();
        vm.expectEmit();
        emit DutchAuction.AuctionFilled(alice, defaultAmount, amountIn);
        dutchAuction.fill{value: amountIn + 1}(defaultAmount, "");
        assertEq(alice.balance, 1, "alice balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), defaultAmount, "ethStrategy balance not assigned correctly");
        assertEq(address(ethStrategy).balance, amountIn, "ethStrategy balance not assigned correctly");
        (uint64 startTime, uint64 duration, uint128 amount, uint256 startPrice, uint256 endPrice) =
            dutchAuction.auction();
        assertEq(startTime, uint64(0), "startTime not assigned correctly");
        assertEq(duration, 0, "duration not assigned correctly");
        assertEq(startPrice, 0, "startPrice not assigned correctly");
        assertEq(endPrice, 0, "endPrice not assigned correctly");
        assertEq(amount, 0, "amount not assigned correctly");
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
        assertEq(usdcToken.balanceOf(address(ethStrategy)), amountIn, "usdcToken balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), _amount, "ethStrategy balance not assigned correctly");
    }
}
