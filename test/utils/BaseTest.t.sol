// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {AtmAuction} from "../../src/AtmAuction.sol";
import {EthStrategy} from "../../src/EthStrategy.sol";
import {USDCToken} from "./USDCToken.sol";
import {AccessManager} from "openzeppelin-contracts/contracts/access/manager/AccessManager.sol";
import {console} from "forge-std/console.sol";

interface IERC20 {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external;
}

contract BaseTest is Test {
    EthStrategy ethStrategy;
    AccessManager accessManager;
    USDCToken usdcToken;
    Account initialOwner;
    Account admin1;
    Account admin2;

    address alice;
    address bob;
    address charlie;

    uint32 defaultTimelockDelay = 1 days;
    uint256 defaultQuorumPercentage = 4;
    uint48 defaultVoteExtension = 1 days;
    uint48 defaultVotingDelay = 1 days;
    uint32 defaultVotingPeriod = 5 days;
    uint256 defaultProposalThreshold = 30_000e18;

    function setUp() public virtual {
        initialOwner = makeAccount("initialOwner");
        admin1 = makeAccount("admin1");
        admin2 = makeAccount("admin2");
        address[] memory admins = new address[](2);
        admins[0] = admin1.addr;
        admins[1] = admin2.addr;
        vm.label(initialOwner.addr, "initialOwner");
        vm.label(admin1.addr, "admin1");
        vm.label(admin2.addr, "admin2");

        usdcToken = new USDCToken();

        accessManager = new AccessManager(initialOwner.addr);
        vm.prank(initialOwner.addr);
        ethStrategy = new EthStrategy(
            defaultTimelockDelay,
            defaultQuorumPercentage,
            defaultVoteExtension,
            defaultVotingDelay,
            defaultVotingPeriod,
            defaultProposalThreshold
        );

        alice = address(1);
        vm.label(alice, "alice");
        bob = address(2);
        vm.label(bob, "bob");
        charlie = address(3);
        vm.label(charlie, "charlie");
    }

    function mintAndApprove(address _to, uint256 _amount, address spender, address _token) public {
        IERC20(_token).mint(_to, _amount);
        vm.prank(_to);
        IERC20(_token).approve(spender, _amount);
    }

    function calculateAmountIn(
        uint128 _amountOut,
        uint64 _startTime,
        uint64 _duration,
        uint128 _startPrice,
        uint128 _endPrice,
        uint64 _currentTime,
        uint8 _decimals
    ) public pure returns (uint256 amountIn) {
        uint64 delta_t = _duration - (_currentTime - _startTime);
        uint128 delta_p = _startPrice - _endPrice;
        uint256 currentPrice = ((delta_p * delta_t) / _duration) + _endPrice;
        amountIn = (_amountOut * currentPrice) / 10 ** _decimals;
        return (amountIn == 0) ? 1 : amountIn;
    }

    function calculateAmountOut(
        uint128 _amountIn,
        uint64 _startTime,
        uint64 _duration,
        uint128 _startPrice,
        uint128 _endPrice,
        uint64 _currentTime,
        uint8 _decimals
    ) public pure returns (uint128) {
        uint64 delta_t = _duration - (_currentTime - _startTime);
        uint128 delta_p = _startPrice - _endPrice;
        uint128 currentPrice = uint128(((delta_p * delta_t) / _duration) + _endPrice);
        return uint128((_amountIn * 10 ** _decimals) / currentPrice);
    }
}
