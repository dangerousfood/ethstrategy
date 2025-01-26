// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AtmAuction} from "../src/AtmAuction.sol";
import {EthStrategy} from "../src/EthStrategy.sol";
import {MockERC20} from "./utils/MockERC20.sol";

contract AtmAuctionTest is Test {
    AtmAuction public auction;
    EthStrategy public strategy;
    MockERC20 public paymentToken;
    address public governor;
    address public user;
    
    event TokensMinted(address indexed buyer, uint128 amount, uint128 price);

    function setUp() public {
        governor = makeAddr("governor");
        user = makeAddr("user");
        
        paymentToken = new MockERC20("Payment Token", "PT", 18);
        strategy = new EthStrategy(governor);
        auction = new AtmAuction(
            address(strategy),
            governor,
            address(paymentToken)
        );
        
        strategy.setMinter(address(auction));
        vm.prank(governor);
        strategy.setMinter(address(auction));
        
        paymentToken.mint(user, 1000 ether);
        vm.prank(user);
        paymentToken.approve(address(auction), type(uint256).max);
    }

    function test_Constructor() public {
        vm.expectRevert("Invalid strategy address");
        new AtmAuction(address(0), governor, address(paymentToken));
        
        vm.expectRevert("Invalid governor address");
        new AtmAuction(address(strategy), address(0), address(paymentToken));
        
        vm.expectRevert("Invalid payment token");
        new AtmAuction(address(strategy), governor, address(0));
    }

    function test_Fill() public {
        uint128 amount = 100;
        uint128 price = 1 ether;
        uint64 startTime = uint64(block.timestamp);
        uint64 duration = 1 hours;

        vm.prank(governor);
        auction.create(amount, price, startTime, duration);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit TokensMinted(user, amount, price);
        auction.fill(amount);

        assertEq(strategy.balanceOf(user), amount);
        assertEq(paymentToken.balanceOf(governor), amount * price);
    }

    function test_FillZeroAmount() public {
        uint128 amount = 0;
        uint128 price = 1 ether;
        uint64 startTime = uint64(block.timestamp);
        uint64 duration = 1 hours;

        vm.prank(governor);
        auction.create(amount, price, startTime, duration);

        vm.prank(user);
        vm.expectRevert("Amount must be positive");
        auction.fill(amount);
    }

    function test_FillOverflow() public {
        uint128 amount = type(uint128).max;
        uint128 price = 2;
        uint64 startTime = uint64(block.timestamp);
        uint64 duration = 1 hours;

        vm.prank(governor);
        auction.create(amount, price, startTime, duration);

        vm.prank(user);
        vm.expectRevert("Arithmetic overflow");
        auction.fill(amount);
    }

    function test_FillInsufficientAllowance() public {
        uint128 amount = 100;
        uint128 price = 1 ether;
        uint64 startTime = uint64(block.timestamp);
        uint64 duration = 1 hours;

        vm.prank(governor);
        auction.create(amount, price, startTime, duration);

        vm.prank(user);
        paymentToken.approve(address(auction), 0);

        vm.prank(user);
        vm.expectRevert();
        auction.fill(amount);
    }

    function test_FillInsufficientBalance() public {
        uint128 amount = 100;
        uint128 price = 1 ether;
        uint64 startTime = uint64(block.timestamp);
        uint64 duration = 1 hours;

        vm.prank(governor);
        auction.create(amount, price, startTime, duration);

        paymentToken.burn(user, paymentToken.balanceOf(user));

        vm.prank(user);
        vm.expectRevert();
        auction.fill(amount);
    }

    function test_FillMintingDisabled() public {
        uint128 amount = 100;
        uint128 price = 1 ether;
        uint64 startTime = uint64(block.timestamp);
        uint64 duration = 1 hours;

        vm.prank(governor);
        auction.create(amount, price, startTime, duration);

        vm.prank(governor);
        strategy.setMinter(address(0));

        vm.prank(user);
        vm.expectRevert("MintFailed");
        auction.fill(amount);
    }
}
