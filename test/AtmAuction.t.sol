pragma solidity ^0.8.20;

import {DutchAuctionTest} from "./DutchAuction.t.sol";
import {AtmAuction} from "../src/AtmAuction.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {console} from "forge-std/console.sol";

contract AtmAuctionTest is DutchAuctionTest {
  function setUp() public override {
    super.setUp();
    dutchAuction = new AtmAuction(
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
    dutchAuction = new AtmAuction(
      address(ethStrategy),
      address(governor),
      address(usdcToken)
    );
    assertEq(dutchAuction.ethStrategy(), address(ethStrategy), "ethStrategy not assigned correctly");
    assertEq(dutchAuction.paymentToken(), address(usdcToken), "paymentToken not assigned correctly");
    assertEq(dutchAuction.owner(), address(governor), "governor not assigned correctly");
  }

  function test_fill_success_1() public override {
    mintAndApprove(alice, defaultAmount * defaultStartPrice / 1e18, address(dutchAuction), address(usdcToken));
    super.test_fill_success_1();

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(governor)), defaultAmount * defaultStartPrice / 1e18, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), defaultAmount, "ethStrategy balance not assigned correctly");
  }

  function test_fill_success_2() public override {
    uint256 _amount = defaultAmount - 1;
    mintAndApprove(alice, _amount * defaultStartPrice/1e18, address(dutchAuction), address(usdcToken));
    super.test_fill_success_2();

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(governor)), _amount * defaultStartPrice / 1e18, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), _amount, "ethStrategy balance not assigned correctly");
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
    uint256 mintAmount = _amount * fillPrice / 1e18;
    mintAndApprove(alice, mintAmount, address(dutchAuction), address(usdcToken));

    fill(_amount, _startTime, _duration, _startPrice, _endPrice, _elapsedTime, _totalAmount);

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(governor)), mintAmount, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), _amount, "ethStrategy balance not assigned correctly");
  }
}
