// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;


import {BaseTest} from "./utils/BaseTest.t.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DutchAuction} from "../../src/DutchAuction.sol";
import {Deposit} from "../../src/Deposit.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {TReentrancyGuard} from "../../lib/TReentrancyGuard/src/TReentrancyGuard.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract DepositTest is BaseTest {
    DutchAuction dutchAuction;
    Deposit deposit;

    uint64 defaultDuration = 1 days;
    uint128 defaultStartPrice = 10_000e6;
    uint128 defaultEndPrice = 3_000e6;
    uint128 defaultAmount = 100e18;

    uint256 defaultConversionPremium = 0;
    uint256 defaultConversionRate = 30_000;
    uint256 defaultDepositCap = 10_000e18;

    Account signer;

    function setUp() public virtual override {
        super.setUp();
        dutchAuction = new DutchAuction(address(ethStrategy), address(usdcToken));
        signer = makeAccount("signer");
        vm.label(signer.addr, "signer");
        deposit = new Deposit(
            address(ethStrategy),
            signer.addr,
            defaultConversionRate,
            defaultConversionPremium,
            defaultDepositCap,
            uint64(block.timestamp)
        );
        vm.prank(address(initialOwner.addr));
        ethStrategy.transferOwnership(address(ethStrategy));
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(deposit), ethStrategy.MINTER_ROLE());
        dutchAuction.grantRoles(admin1.addr, dutchAuction.ADMIN_ROLE());
        dutchAuction.grantRoles(admin2.addr, dutchAuction.ADMIN_ROLE());
        vm.stopPrank();
    }

    function test_deposit_success() public {
        uint256 depositAmount = 1e18;
        bytes memory signature = getSignature(alice);
        vm.deal(alice, depositAmount);
        vm.startPrank(alice);
        vm.expectEmit();
        emit ERC20.Transfer(address(0), alice, depositAmount * deposit.CONVERSION_RATE());
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();

        uint256 conversionRate = deposit.CONVERSION_RATE();
        assertEq(ethStrategy.balanceOf(alice), conversionRate * depositAmount, "balance of alice incorrect");
        assertEq(deposit.depositCap(), defaultDepositCap - depositAmount, "deposit cap incorrect");
        assertEq(deposit.hasRedeemed(alice), true, "alice hasn't redeemed");
        assertEq(address(ethStrategy).balance, depositAmount, "ethStrategy balance incorrect");
    }

    function test_deposit_success_whiteListDisabled() public {
        deposit = new Deposit(
            address(ethStrategy),
            address(0),
            defaultConversionRate,
            defaultConversionPremium,
            defaultDepositCap,
            uint64(block.timestamp)
        );
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRoles(address(deposit), ethStrategy.MINTER_ROLE());
        vm.stopPrank();
        uint256 depositAmount = 1e18;
        vm.deal(alice, depositAmount);
        vm.startPrank(alice);
        vm.expectEmit();
        emit ERC20.Transfer(address(0), alice, depositAmount * deposit.CONVERSION_RATE());
        deposit.deposit{value: depositAmount}(new bytes(0));
        vm.stopPrank();

        uint256 conversionRate = deposit.CONVERSION_RATE();
        assertEq(ethStrategy.balanceOf(alice), conversionRate * depositAmount, "balance of alice incorrect");
        assertEq(deposit.depositCap(), defaultDepositCap - depositAmount, "deposit cap incorrect");
        assertEq(address(ethStrategy).balance, depositAmount, "ethStrategy balance incorrect");
    }

    function test_deposit_DepositNotStarted() public {
        deposit = new Deposit(
            address(ethStrategy),
            address(0),
            defaultConversionRate,
            defaultConversionPremium,
            defaultDepositCap,
            uint64(block.timestamp + 1)
        );
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRoles(address(deposit), ethStrategy.MINTER_ROLE());
        vm.stopPrank();
        uint256 depositAmount = 1e18;
        bytes memory signature = getSignature(alice);
        vm.deal(alice, depositAmount);
        vm.startPrank(alice);
        vm.expectRevert(Deposit.DepositNotStarted.selector);
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();
    }

    function test_deposit_DepositCapExceeded() public {
        uint256 depositAmount = defaultDepositCap + 1;
        bytes memory signature = getSignature(alice);
        vm.deal(alice, depositAmount);
        vm.startPrank(alice);
        vm.expectRevert(Deposit.DepositCapExceeded.selector);
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();

        assertEq(deposit.depositCap(), defaultDepositCap, "deposit cap incorrect");
        assertEq(deposit.hasRedeemed(alice), false, "alice has redeemed");
        assertEq(address(ethStrategy).balance, 0, "ethStrategy balance incorrect");
        assertEq(ethStrategy.balanceOf(alice), 0, "alice balance incorrect");
        assertEq(address(deposit).balance, 0, "deposit balance incorrect");
    }

    function test_deposit_AlreadyRedeemed() public {
        uint256 depositAmount = 1e18;
        bytes memory signature = getSignature(alice);
        vm.deal(alice, depositAmount * 2);
        vm.startPrank(alice);
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(Deposit.AlreadyRedeemed.selector);
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();

        assertEq(deposit.depositCap(), defaultDepositCap - depositAmount, "deposit cap incorrect");
        assertEq(deposit.hasRedeemed(alice), true, "alice has redeemed");
        assertEq(address(ethStrategy).balance, depositAmount, "ethStrategy balance incorrect");
        assertEq(ethStrategy.balanceOf(alice), depositAmount * deposit.CONVERSION_RATE(), "alice balance incorrect");
        assertEq(address(deposit).balance, 0, "deposit balance incorrect");
    }

    function test_deposit_DepositAmountTooLow() public {
        uint256 depositAmount = 1e18 - 1;
        bytes memory signature = getSignature(alice);
        vm.deal(alice, depositAmount);
        vm.startPrank(alice);
        vm.expectRevert(Deposit.DepositAmountTooLow.selector);
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();

        assertEq(deposit.depositCap(), defaultDepositCap, "deposit cap incorrect");
        assertEq(deposit.hasRedeemed(alice), false, "alice has redeemed");
        assertEq(address(ethStrategy).balance, 0, "ethStrategy balance incorrect");
        assertEq(ethStrategy.balanceOf(alice), 0, "alice balance incorrect");
        assertEq(address(deposit).balance, 0, "deposit balance incorrect");
    }

    function test_deposit_InvalidSignature() public {
        uint256 depositAmount = 1e18;
        vm.deal(alice, depositAmount);
        vm.startPrank(alice);
        vm.expectRevert(Deposit.InvalidSignature.selector);
        deposit.deposit{value: depositAmount}(new bytes(0));
        vm.stopPrank();

        assertEq(deposit.depositCap(), defaultDepositCap, "deposit cap incorrect");
        assertEq(deposit.hasRedeemed(alice), false, "alice has redeemed");
        assertEq(address(ethStrategy).balance, 0, "ethStrategy balance incorrect");
        assertEq(ethStrategy.balanceOf(alice), 0, "alice balance incorrect");
        assertEq(address(deposit).balance, 0, "deposit balance incorrect");
    }

    function test_deposit_DepositAmountTooHigh() public {
        uint256 depositAmount = 100e18 + 1;
        bytes memory signature = getSignature(alice);
        vm.deal(alice, depositAmount);
        vm.startPrank(alice);
        vm.expectRevert(Deposit.DepositAmountTooHigh.selector);
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();

        assertEq(deposit.depositCap(), defaultDepositCap, "deposit cap incorrect");
        assertEq(deposit.hasRedeemed(alice), false, "alice has redeemed");
        assertEq(address(ethStrategy).balance, 0, "ethStrategy balance incorrect");
        assertEq(ethStrategy.balanceOf(alice), 0, "alice balance incorrect");
        assertEq(address(deposit).balance, 0, "deposit balance incorrect");
    }

    function test_deposit_DepositFailed() public {
        uint256 depositAmount = 1e18;
        bytes memory signature = getSignature(alice);
        OwnerDepositRejector ownerDepositRejector = new OwnerDepositRejector();
        vm.startPrank(address(ethStrategy));
        deposit.transferOwnership(address(ownerDepositRejector));
        vm.stopPrank();
        vm.deal(alice, depositAmount);
        vm.startPrank(alice);
        vm.expectRevert(Deposit.DepositFailed.selector);
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();

        assertEq(deposit.depositCap(), defaultDepositCap, "deposit cap incorrect");
        assertEq(deposit.hasRedeemed(alice), false, "alice has redeemed");
        assertEq(address(ethStrategy).balance, 0, "ethStrategy balance incorrect");
        assertEq(ethStrategy.balanceOf(alice), 0, "alice balance incorrect");
        assertEq(address(deposit).balance, 0, "deposit balance incorrect");
    }

    function test_deposit_ReentrancyForbidden() public {
        ReentrantDeposit reentrantDeposit = new ReentrantDeposit(deposit);
        vm.prank(address(ethStrategy));
        deposit.transferOwnership(address(reentrantDeposit));
        uint256 depositAmount = 1e18;
        bytes memory signature = getSignature(alice);
        vm.deal(alice, depositAmount);
        vm.startPrank(alice);
        vm.expectRevert(Deposit.DepositFailed.selector);
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();
    }

    function test_deposit_InvalidConversionPremium() public {
        uint256 conversionPremium = 100_01;
        vm.expectRevert(Deposit.InvalidConversionPremium.selector);
        deposit = new Deposit(
            address(ethStrategy),
            signer.addr,
            defaultConversionRate,
            conversionPremium,
            defaultDepositCap,
            uint64(block.timestamp)
        );
    }

    function test_setSigner_success() public {
        vm.startPrank(address(ethStrategy));
        deposit.setSigner(bob);
        vm.stopPrank();
        assertEq(deposit.signer(), bob, "signer incorrect");
    }

    function test_setSigner_Unauthorized() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        deposit.setSigner(bob);
        assertEq(deposit.signer(), signer.addr, "signer incorrect");
    }

    function test_receive_InvalidCall() public {
        vm.deal(alice, 1e18);
        vm.prank(alice);
        vm.expectRevert(Deposit.InvalidCall.selector);
        payable(address(deposit)).call{value: 1e18}("");
    }

    function getSignature(address _to) public view returns (bytes memory) {
        bytes32 hash = SignatureCheckerLib.toEthSignedMessageHash(abi.encodePacked(_to));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, hash);
        return abi.encodePacked(r, s, v);
    }

    function test_whitelist_example_signature() public {
        vm.startPrank(address(ethStrategy));
        address _signer = 0x4ADaB48B2FfCC7aDdCEF346fE56Af3812813001c;
        deposit.setSigner(_signer);
        vm.stopPrank();
        address depositor = 0x2Fc9478c3858733b6e9b87458D71044A2071a300;
        uint256 depositAmount = 1e18;
        bytes memory signature =
            hex"85f7247810d04fd78e94915ca7a46e108f55cb0c3c2b9715cfbef293a62c3f9109fcca42b389a4c9ce7348059cd5103a252ab8125c2a648bd6f0ce12718ed1a71c";
        vm.deal(depositor, depositAmount);
        vm.startPrank(depositor);
        vm.expectEmit();
        emit ERC20.Transfer(address(0), depositor, depositAmount * deposit.CONVERSION_RATE());
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();

        uint256 conversionRate = deposit.CONVERSION_RATE();
        assertEq(ethStrategy.balanceOf(depositor), conversionRate * depositAmount, "balance of alice incorrect");
        assertEq(deposit.depositCap(), defaultDepositCap - depositAmount, "deposit cap incorrect");
        assertEq(deposit.hasRedeemed(depositor), true, "alice hasn't redeemed");
        assertEq(address(ethStrategy).balance, depositAmount, "ethStrategy balance incorrect");
    }

    function testFuzz_deposit(
        uint256 depositAmount,
        uint256 depositCap,
        uint256 conversionRate,
        uint256 conversionPremium
    ) public {
        depositAmount = bound(depositAmount, 1e18, 100e18);
        depositCap = bound(depositCap, 1e18, 10_000e18);
        conversionPremium = bound(conversionPremium, 0, 100_00);
        conversionRate = bound(conversionRate, 1, defaultConversionRate);
        vm.assume(depositAmount <= depositCap);

        uint256 DENOMINATOR_BP = deposit.DENOMINATOR_BP();
        deposit = new Deposit(
            address(ethStrategy), signer.addr, conversionRate, conversionPremium, depositCap, uint64(block.timestamp)
        );

        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRoles(address(deposit), ethStrategy.MINTER_ROLE());
        vm.stopPrank();

        bytes memory signature = getSignature(alice);
        vm.deal(alice, depositAmount);
        vm.startPrank(alice);
        vm.expectEmit();
        emit ERC20.Transfer(
            address(0),
            alice,
            (depositAmount * deposit.CONVERSION_RATE() * (DENOMINATOR_BP - conversionPremium)) / DENOMINATOR_BP
        );
        deposit.deposit{value: depositAmount}(signature);
        vm.stopPrank();

        assertEq(deposit.depositCap(), depositCap - depositAmount, "deposit cap incorrect");
        assertEq(deposit.hasRedeemed(alice), true, "alice has redeemed");
        assertEq(address(ethStrategy).balance, depositAmount, "governor balance incorrect");
        assertEq(
            ethStrategy.balanceOf(alice),
            (depositAmount * deposit.CONVERSION_RATE() * (DENOMINATOR_BP - conversionPremium)) / DENOMINATOR_BP,
            "alice balance incorrect"
        );
        assertEq(address(deposit).balance, 0, "deposit balance incorrect");
    }
}

contract OwnerDepositRejector {
    error Rejected();

    fallback() external payable {
        revert Rejected();
    }
}

contract ReentrantDeposit {
    Deposit deposit;

    constructor(Deposit _deposit) {
        deposit = _deposit;
    }

    fallback() external payable {
        deposit.deposit{value: msg.value}(new bytes(0));
    }
}
