// // SPDX-License-Identifier: Apache 2.0
// pragma solidity ^0.8.26;

// import {BaseTest} from "./utils/BaseTest.t.sol";
// import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
// import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
// import {DutchAuction} from "../../src/DutchAuction.sol";
// import {Deposit} from "../../src/Deposit.sol";
// import {ERC20} from "solady/src/tokens/ERC20.sol";
// import {Ownable} from "solady/src/auth/Ownable.sol";
// import {TReentrancyGuard} from "../../lib/TReentrancyGuard/src/TReentrancyGuard.sol";
// import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
// import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

pragma solidity ^0.8.26;

import {DutchAuctionTest} from "./DutchAuction.t.sol";
import {AtmAuction} from "../src/AtmAuction.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {Deposit} from "../src/Deposit.sol";
import {EthStrategy} from "../src/EthStrategy.sol";

contract DepositTest is DutchAuctionTest {
    function setUp() public override {
        super.setUp();
        vm.prank(admin1.addr);
        dutchAuction = new Deposit(address(ethStrategy), address(usdcToken), address(0));
        vm.startPrank(address(initialOwner.addr));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        vm.startPrank(address(ethStrategy));
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        vm.stopPrank();
        defaultStartPrice = 33_333_333_333_334;
        defaultEndPrice = 33_333_333_333_334;
        defaultAmount = 30_000e18;
    }

    function test_constructor_success() public {
        dutchAuction = new Deposit(address(ethStrategy), address(usdcToken), address(0));
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

        assertEq(alice.balance, 0, "balance not assigned correctly");
        assertEq(
            usdcToken.balanceOf(address(ethStrategy)),
            defaultAmount * defaultStartPrice / (10 ** ethStrategy.decimals()),
            "balance not assigned correctly"
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

    function test_startAuction_invalidStartPrice_1() public override {
        // I'm not proud of myself for this one
        defaultEndPrice = defaultEndPrice - 1;
        super.test_startAuction_invalidStartPrice_1();
    }

    function test_fill_revert_DepositAmountTooHigh() public virtual {
        defaultAmount = defaultAmount + 1;

        uint128 amountOut = calculateAmountOut(
            defaultAmount,
            uint64(block.timestamp),
            defaultDuration,
            defaultStartPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        vm.startPrank(admin1.addr);
        dutchAuction.startAuction(
            uint64(block.timestamp), defaultDuration, defaultStartPrice, defaultEndPrice, amountOut
        );
        vm.stopPrank();
        mintAndApprove(alice, defaultAmount, address(dutchAuction), address(dutchAuction.paymentToken()));
        vm.prank(alice);
        vm.expectRevert(Deposit.DepositAmountTooHigh.selector);
        dutchAuction.fill(amountOut, "");
    }

    function test_initiateGovernance_success() public {
        vm.startPrank(initialOwner.addr);
        ethStrategy = new EthStrategy(
            defaultTimelockDelay,
            defaultQuorumPercentage,
            defaultVoteExtension,
            defaultVotingDelay,
            defaultVotingPeriod,
            defaultProposalThreshold
        );
        dutchAuction = new Deposit(address(ethStrategy), address(usdcToken), address(0));
        ethStrategy.transferOwnership(address(ethStrategy));
        vm.stopPrank();
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.GOV_INIT_ADMIN_ROLE());
        dutchAuction.grantRoles(admin1.addr, dutchAuction.DA_ADMIN_ROLE());
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        vm.stopPrank();
        Deposit(payable(dutchAuction)).initiateGovernance();
        assertEq(ethStrategy.governanceInitiated(), true, "governanceInitiated not assigned correctly");
    }

    function test_initiateGovernance_revert_AuctionNotEnded() public {
        vm.startPrank(initialOwner.addr);
        ethStrategy = new EthStrategy(
            defaultTimelockDelay,
            defaultQuorumPercentage,
            defaultVoteExtension,
            defaultVotingDelay,
            defaultVotingPeriod,
            defaultProposalThreshold
        );
        dutchAuction = new Deposit(address(ethStrategy), address(usdcToken), address(0));
        ethStrategy.transferOwnership(address(ethStrategy));
        vm.stopPrank();
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.GOV_INIT_ADMIN_ROLE());
        dutchAuction.grantRoles(admin1.addr, dutchAuction.DA_ADMIN_ROLE());
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        vm.stopPrank();
        test_startAuction_success_1();
        vm.expectRevert(Deposit.AuctionNotEnded.selector);
        Deposit(payable(dutchAuction)).initiateGovernance();
    }

    function testFuzz_startPrice(uint128 _startPrice) public virtual override {
        vm.assume(_startPrice > 0);
        vm.assume(_startPrice >= defaultEndPrice);
        vm.assume(_startPrice <= (type(uint128).max / defaultAmount));
        uint128 amountIn = calculateAmountIn(
            defaultAmount,
            uint64(block.timestamp),
            defaultDuration,
            _startPrice,
            defaultEndPrice,
            uint64(block.timestamp),
            dutchAuction.decimals()
        );
        vm.assume(amountIn < 100e18);
        uint64 currentTime = uint64(block.timestamp);
        fill(defaultAmount - 1, currentTime, defaultDuration, _startPrice, defaultEndPrice, currentTime, defaultAmount);
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

    function test_whitelist_example_signature() public virtual override {
        address filler = 0x2Fc9478c3858733b6e9b87458D71044A2071a300;
        mintAndApprove(filler, defaultAmount, address(dutchAuction), address(dutchAuction.paymentToken()));
        super.test_whitelist_example_signature();
    }
}
