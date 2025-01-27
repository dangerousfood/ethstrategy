pragma solidity ^0.8.20;

import {DutchAuctionTest} from "./DutchAuction.t.sol";
import {BondAuction} from "../src/BondAuction.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {console} from "forge-std/console.sol";

contract BondAuctionTest is DutchAuctionTest {
  function setUp() public override {
    super.setUp();
    dutchAuction = new BondAuction(
      address(ethStrategy),
      address(governor),
      address(usdcToken)
    );
    vm.startPrank(address(governor));
    ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
    dutchAuction.grantRoles(admin1.addr, dutchAuction.ADMIN_ROLE());
    dutchAuction.grantRoles(admin2.addr, dutchAuction.ADMIN_ROLE());
    vm.stopPrank();
  }

  function test_constructor_success() public {
    dutchAuction = new BondAuction(
      address(ethStrategy),
      address(governor),
      address(usdcToken)
    );
    assertEq(dutchAuction.ethStrategy(), address(ethStrategy), "ethStrategy not assigned correctly");
    assertEq(dutchAuction.paymentToken(), address(usdcToken), "paymentToken not assigned correctly");
    assertEq(dutchAuction.owner(), address(governor), "governor not assigned correctly");
  }

  function test_fill_success_1() public override {
    mintAndApprove(alice, defaultAmount * defaultStartPrice / (10**ethStrategy.decimals()), address(dutchAuction), address(usdcToken));
    super.test_fill_success_1();

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), defaultAmount * defaultStartPrice / (10**ethStrategy.decimals()), "usdcToken balance not assigned correctly");
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, defaultAmount, "amount not assigned correctly");
    assertEq(price, defaultStartPrice, "price not assigned correctly");
    assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
  }

  function test_fill_success_2() public override {
    uint256 _amount = defaultAmount - 1;
    mintAndApprove(alice, _amount * defaultStartPrice / (10**ethStrategy.decimals()), address(dutchAuction), address(usdcToken));
    super.test_fill_success_2();

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), _amount * defaultStartPrice / (10**ethStrategy.decimals()), "usdcToken balance not assigned correctly");
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, _amount, "amount not assigned correctly");
    assertEq(price, defaultStartPrice, "price not assigned correctly");
    assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
  }

  function test_redeem_success() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(block.timestamp + defaultDuration + 1);
    vm.prank(alice);
    bondAuction.redeem();
    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), defaultAmount, "ethStrategy balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(governor)), defaultAmount * defaultStartPrice / (10**ethStrategy.decimals()), "usdcToken balance not assigned correctly");

    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, 0, "amount not assigned correctly");
    assertEq(price, 0, "price not assigned correctly");
    assertEq(startRedemption, 0, "startRedemption not assigned correctly");
  }

  function test_redeem_noBondToRedeem() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(block.timestamp + defaultDuration + 1);
    vm.expectRevert(BondAuction.NoBondToRedeem.selector);
    bondAuction.redeem();
  }

  function test_redeem_redemptionWindowNotStarted() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(block.timestamp + defaultDuration - 1);
    vm.prank(alice);
    vm.expectRevert(BondAuction.RedemptionWindowNotStarted.selector);
    bondAuction.redeem();
    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, defaultAmount, "amount not assigned correctly");
    assertEq(price, defaultStartPrice, "price not assigned correctly");
    assertEq(startRedemption, block.timestamp + 1, "startRedemption not assigned correctly");
  }

  function test_redeem_redemptionWindowPassed() public {
    uint256 startTime = block.timestamp;
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(startTime + defaultDuration + bondAuction.REDEMPTION_WINDOW() + 1);
    vm.prank(alice);
    vm.expectRevert(BondAuction.RedemptionWindowPassed.selector);
    bondAuction.redeem();

    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, defaultAmount, "amount not assigned correctly");
    assertEq(price, defaultStartPrice, "price not assigned correctly");
    assertEq(startRedemption, startTime + defaultDuration, "startRedemption not assigned correctly");
  }

  function test_withdraw_success() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(block.timestamp + defaultDuration + 1);
    vm.prank(alice);
    bondAuction.withdraw();
    assertEq(usdcToken.balanceOf(alice), defaultAmount * defaultStartPrice / (10**ethStrategy.decimals()), "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), 0, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), 0, "ethStrategy balance not assigned correctly");

    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, 0, "amount not assigned correctly");
    assertEq(price, 0, "price not assigned correctly");
    assertEq(startRedemption, 0, "startRedemption not assigned correctly");
  }

  function test_withdraw_noBondToWithdraw() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(block.timestamp + defaultDuration + 1);
    vm.expectRevert(BondAuction.NoBondToWithdraw.selector);
    bondAuction.withdraw();
    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, defaultAmount, "amount not assigned correctly");
    assertEq(price, defaultStartPrice, "price not assigned correctly");
    assertEq(startRedemption, block.timestamp - 1, "startRedemption not assigned correctly");
  }

  function test_withdraw_redemptionWindowNotStarted() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.expectRevert(BondAuction.RedemptionWindowNotStarted.selector);
    vm.prank(alice);
    bondAuction.withdraw();
    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, defaultAmount, "amount not assigned correctly");
    assertEq(price, defaultStartPrice, "price not assigned correctly");
    assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
  }

  function test_fill_unredeemedBond() public {
    uint64 expectedStartTime = uint64(block.timestamp);
    uint128 _amount = defaultAmount / 2;
    mintAndApprove(alice, _amount * defaultStartPrice / (10**ethStrategy.decimals()), address(dutchAuction), address(usdcToken));
    
    test_startAuction_success_1();
    vm.prank(alice);
    vm.expectEmit();
    emit DutchAuction.AuctionFilled(alice, _amount, defaultStartPrice);
    dutchAuction.fill(_amount);

    {
      (uint64 startTime, uint64 duration, uint128 startPrice, uint128 endPrice, uint128 amount) = dutchAuction.auction();
      assertEq(startTime, expectedStartTime, "startTime not assigned correctly");
      assertEq(duration, defaultDuration, "duration not assigned correctly");
      assertEq(startPrice, defaultStartPrice, "startPrice not assigned correctly");
      assertEq(endPrice, defaultEndPrice, "endPrice not assigned correctly");
      assertEq(amount, defaultAmount - _amount, "amount not assigned correctly");
    }

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), _amount * defaultStartPrice / (10**ethStrategy.decimals()), "usdcToken balance not assigned correctly");
    BondAuction bondAuction = BondAuction(address(dutchAuction));

    {
      (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
      assertEq(amount, _amount, "amount not assigned correctly");
      assertEq(price, defaultStartPrice, "price not assigned correctly");
      assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
    }

    mintAndApprove(alice, _amount * defaultStartPrice, address(dutchAuction), address(usdcToken));
    vm.prank(alice);
    vm.expectRevert(BondAuction.UnredeemedBond.selector);
    dutchAuction.fill(_amount);
  }

  function testFuzz_fill(uint128 _amount, uint64 _startTime, uint64 _duration, uint128 _startPrice, uint128 _endPrice, uint64 _elapsedTime, uint128 _totalAmount) public override {
    vm.assume(_amount < _totalAmount);
    vm.assume(_amount > 0);
    vm.assume(_startTime > block.timestamp);
    vm.assume(_startTime < block.timestamp + dutchAuction.MAX_START_TIME_WINDOW());
    vm.assume(_duration > 0);
    vm.assume(_duration < dutchAuction.MAX_DURATION());
    vm.assume(_startPrice > 0);
    vm.assume(_endPrice > 0);
    vm.assume(_startPrice >= _endPrice);
    vm.assume(_elapsedTime >= _startTime);
    vm.assume(_elapsedTime < _startTime + _duration);
    vm.assume(_startPrice <= (type(uint128).max / _totalAmount));
    uint64 delta_t = _duration - (_elapsedTime - _startTime);
    uint128 delta_p = _startPrice - _endPrice;
    if(delta_p == 0) {
      delta_p = 1;
    }
    vm.assume(delta_t <= type(uint128).max / delta_p);

    uint128 fillPrice = calculateFillPrice(_startTime, _duration, _startPrice, _endPrice, _elapsedTime);
    uint256 mintAmount = _amount * fillPrice / (10**ethStrategy.decimals());
    mintAndApprove(alice, mintAmount, address(dutchAuction), address(usdcToken));

    fill(_amount, _startTime, _duration, _startPrice, _endPrice, _elapsedTime, _totalAmount);

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), mintAmount, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), 0, "ethStrategy balance not assigned correctly");
    
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    uint256 __amount = _amount; // stack cycling
    assertEq(amount, __amount, "amount not assigned correctly");
    assertEq(price, fillPrice, "price not assigned correctly");
    uint64 __startTime = _startTime; // stack cycling
    uint64 __duration = _duration; // stack cycling
    assertEq(startRedemption, __startTime + __duration, "startRedemption not assigned correctly");
  }
}

