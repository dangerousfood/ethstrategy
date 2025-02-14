// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {BaseTest} from "./utils/BaseTest.t.sol";
import {DutchAuction} from "../../src/DutchAuction.sol";
import {Ownable} from "solady/src/auth/OwnableRoles.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {NavOptions} from "../../src/NavOptions.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {EthStrategy} from "../../src/EthStrategy.sol";

contract NavOptionsTest is BaseTest {
    NavOptions navOptions;

    function setUp() public override {
        super.setUp();
        navOptions = new NavOptions(address(ethStrategy));
        vm.startPrank(initialOwner.addr);
        ethStrategy.grantRoles(address(navOptions), ethStrategy.MINTER_ROLE());
        vm.stopPrank();
    }

    function test_constructor_success() public {
        navOptions = new NavOptions(address(ethStrategy));
        assertEq(navOptions.ETH_STRATEGY(), address(ethStrategy), "ETH_STRATEGY not assigned correctly");
        assertEq(navOptions.owner(), address(ethStrategy), "owner not assigned correctly");
    }

    function test_name_success() public {
        assertEq(navOptions.name(), "EthStrategy Options", "name not assigned correctly");
    }

    function test_symbol_success() public {
        assertEq(navOptions.symbol(), "oETHxr", "symbol not assigned correctly");
    }

    function test_mint_success() public {
        mintOptions(alice, 100e18);
        assertEq(navOptions.balanceOf(alice), 100e18, "balance not assigned correctly");
    }

    function test_mint_revert_unauthorized() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        navOptions.mint(alice, 100e18);
    }

    function test_redeem_success_1() public {
        mintOptions(alice, 100e18);
        vm.prank(alice);
        navOptions.redeem(100e18);
        assertEq(navOptions.balanceOf(alice), 0, "balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), 100e18, "balance not assigned correctly");
    }

    function test_redeem_success_2() public {
        mintOptions(alice, 100e18);
        addNavToken(address(usdcToken));
        mintAndApprove(alice, 100e18, address(navOptions), address(usdcToken));
        vm.prank(address(navOptions));
        ethStrategy.mint(bob, 100e18);
        vm.startPrank(alice);
        usdcToken.transfer(address(ethStrategy), 50e18);
        navOptions.redeem(100e18);
        vm.stopPrank();
        assertEq(navOptions.balanceOf(alice), 0, "balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), 100e18, "balance not assigned correctly");
        assertEq(usdcToken.balanceOf(alice), 0, "balance not assigned correctly");
        assertEq(usdcToken.balanceOf(address(ethStrategy)), 100e18, "balance not assigned correctly");
    }

    function test_redeem_success_3() public {
        mintOptions(alice, 100e18);
        addNavToken(address(usdcToken));
        vm.deal(address(ethStrategy), 50e18);
        vm.deal(alice, 50e18);
        mintAndApprove(alice, 100e18, address(navOptions), address(usdcToken));
        vm.prank(address(navOptions));
        ethStrategy.mint(bob, 100e18);
        vm.startPrank(alice);
        usdcToken.transfer(address(ethStrategy), 50e18);
        navOptions.redeem{value: 50e18}(100e18);
        vm.stopPrank();
        assertEq(navOptions.balanceOf(alice), 0, "balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), 100e18, "balance not assigned correctly");
        assertEq(usdcToken.balanceOf(alice), 0, "balance not assigned correctly");
        assertEq(usdcToken.balanceOf(address(ethStrategy)), 100e18, "balance not assigned correctly");
        assertEq(address(ethStrategy).balance, 100e18, "balance not assigned correctly");
        assertEq(alice.balance, 0, "balance not assigned correctly");
    }

    function test_redeem_success_4() public {
        mintOptions(alice, 100e18);
        addNavToken(address(usdcToken));
        vm.deal(address(ethStrategy), 50e18);
        vm.deal(alice, 50e18 + 1);
        mintAndApprove(alice, 100e18, address(navOptions), address(usdcToken));
        vm.prank(address(navOptions));
        ethStrategy.mint(bob, 100e18);
        vm.startPrank(alice);
        usdcToken.transfer(address(ethStrategy), 50e18);
        navOptions.redeem{value: 50e18 + 1}(100e18);
        vm.stopPrank();
        assertEq(navOptions.balanceOf(alice), 0, "balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(alice), 100e18, "balance not assigned correctly");
        assertEq(usdcToken.balanceOf(alice), 0, "balance not assigned correctly");
        assertEq(usdcToken.balanceOf(address(ethStrategy)), 100e18, "balance not assigned correctly");
        assertEq(address(ethStrategy).balance, 100e18, "balance not assigned correctly");
        assertEq(alice.balance, 1, "balance not assigned correctly");
    }

    function test_getNavValue_success_1() public {
        mintOptions(alice, 100e18);
        addNavToken(address(usdcToken));
        mintAndApprove(alice, 100e18, address(navOptions), address(usdcToken));
        vm.prank(address(navOptions));
        ethStrategy.mint(bob, 100e18);
        vm.startPrank(alice);
        usdcToken.transfer(address(ethStrategy), 50e18);
        vm.stopPrank();

        NavOptions.NavValue[] memory navValues = navOptions.getNavValue(100e18);
        assertEq(navValues.length, 1, "navValues length not assigned correctly");
        assertEq(navValues[0].token, address(usdcToken), "token not assigned correctly");
        assertEq(navValues[0].value, 50e18, "value not assigned correctly");
    }

    function test_getNavValue_success_2() public {
        mintOptions(alice, 1);
        addNavToken(address(usdcToken));
        vm.deal(address(ethStrategy), 1);
        mintAndApprove(address(ethStrategy), 1, address(navOptions), address(usdcToken));
        vm.prank(address(navOptions));
        ethStrategy.mint(bob, 100e18);

        NavOptions.NavValue[] memory navValues = navOptions.getNavValue(1);
        assertEq(navValues.length, 2, "navValues length not assigned correctly");
        assertEq(navValues[0].token, address(usdcToken), "token not assigned correctly");
        assertEq(navValues[0].value, 1, "value not assigned correctly");
        assertEq(navValues[1].token, address(0), "token not assigned correctly");
        assertEq(navValues[1].value, 1, "value not assigned correctly");
    }

    function test_getNavValue_success_3() public {
        mintOptions(alice, 100e18);
        addNavToken(address(usdcToken));
        vm.prank(address(navOptions));
        ethStrategy.mint(bob, 100e18);

        NavOptions.NavValue[] memory navValues = navOptions.getNavValue(100e18);
        assertEq(navValues.length, 0, "navValues length not assigned correctly");
    }

    function test_getNavValue_revert_amountIsZero() public {
        vm.expectRevert(NavOptions.AmountIsZero.selector);
        navOptions.getNavValue(0);
    }

    function test_addNavToken_success() public {
        addNavToken(address(usdcToken));
        addNavToken(address(address(2)));
        address[] memory navTokens = navOptions.getNavTokens();
        assertEq(navTokens.length, 2, "navTokens length not assigned correctly");
        assertEq(navTokens[0], address(usdcToken), "token not assigned correctly");
        assertEq(navTokens[1], address(address(2)), "token not assigned correctly");
    }

    function test_addNavToken_revert_unauthorized() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        navOptions.addNavToken(address(usdcToken));
    }

    function test_removeNavToken_success_1() public {
        addNavToken(address(usdcToken));
        addNavToken(address(address(2)));
        address[] memory navTokens = navOptions.getNavTokens();
        assertEq(navTokens.length, 2, "navTokens length not assigned correctly");
        assertEq(navTokens[0], address(usdcToken), "token not assigned correctly");
        assertEq(navTokens[1], address(address(2)), "token not assigned correctly");
        removeNavToken(address(usdcToken));
        navTokens = navOptions.getNavTokens();
        assertEq(navTokens.length, 1, "navTokens length not assigned correctly");
        assertEq(navTokens[0], address(address(2)), "token not assigned correctly");
    }

    function test_removeNavToken_success_2() public {
        addNavToken(address(usdcToken));
        addNavToken(address(address(2)));
        address[] memory navTokens = navOptions.getNavTokens();
        assertEq(navTokens.length, 2, "navTokens length not assigned correctly");
        assertEq(navTokens[0], address(usdcToken), "token not assigned correctly");
        assertEq(navTokens[1], address(address(2)), "token not assigned correctly");
        removeNavToken(address(2));
        navTokens = navOptions.getNavTokens();
        assertEq(navTokens.length, 1, "navTokens length not assigned correctly");
        assertEq(navTokens[0], address(usdcToken), "token not assigned correctly");
    }

    function test_removeNavToken_success_3() public {
        addNavToken(address(usdcToken));
        addNavToken(address(address(2)));
        address[] memory navTokens = navOptions.getNavTokens();
        assertEq(navTokens.length, 2, "navTokens length not assigned correctly");
        assertEq(navTokens[0], address(usdcToken), "token not assigned correctly");
        assertEq(navTokens[1], address(address(2)), "token not assigned correctly");
        removeNavToken(address(3));
        navTokens = navOptions.getNavTokens();
        assertEq(navTokens.length, 2, "navTokens length not assigned correctly");
        assertEq(navTokens[0], address(usdcToken), "token not assigned correctly");
        assertEq(navTokens[1], address(address(2)), "token not assigned correctly");
    }

    function test_removeNavToken_success_4() public {
        removeNavToken(address(3));
        address[] memory navTokens = navOptions.getNavTokens();
        assertEq(navTokens.length, 0, "navTokens length not assigned correctly");
    }

    function test_removeNavToken_revert_unauthorized() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        navOptions.removeNavToken(address(usdcToken));
    }

    function mintOptions(address to, uint256 amount) public {
        vm.startPrank(address(ethStrategy));
        navOptions.grantRoles(to, navOptions.MINTER_ROLE());
        vm.stopPrank();
        vm.prank(to);
        navOptions.mint(to, amount);
    }

    function addNavToken(address token) public {
        vm.startPrank(address(ethStrategy));
        navOptions.grantRoles(alice, navOptions.NAV_ADMIN_ROLE());
        vm.stopPrank();
        vm.prank(alice);
        navOptions.addNavToken(token);
    }

    function removeNavToken(address token) public {
        vm.startPrank(address(ethStrategy));
        navOptions.grantRoles(alice, navOptions.NAV_ADMIN_ROLE());
        vm.stopPrank();
        vm.prank(alice);
        navOptions.removeNavToken(token);
    }
}
