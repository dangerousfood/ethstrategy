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
        uint128 amountIn = calculateAmountIn(
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
        uint128 amountIn = calculateAmountIn(
            _amount, _startTime, _duration, _startPrice, _endPrice, _elapsedTime, dutchAuction.decimals()
        );
        mintAndApprove(alice, amountIn, address(dutchAuction), address(dutchAuction.paymentToken()));
        super.fill(_amount, _startTime, _duration, _startPrice, _endPrice, _elapsedTime, _totalAmount);
        assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
        assertEq(usdcToken.balanceOf(address(ethStrategy)), amountIn, "usdcToken balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), _amount, "ethStrategy balance not assigned correctly");
    }
}
