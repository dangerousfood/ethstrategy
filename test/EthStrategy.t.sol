// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {BaseTest} from "./utils/BaseTest.t.sol";
import {IGovernor, Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DutchAuction} from "../../src/DutchAuction.sol";
import {IERC20Errors, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EthStrategy} from "../src/EthStrategy.sol";
import {Ownable} from "solady/src/auth/OwnableRoles.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {Ownable, OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {console} from "forge-std/console.sol";

contract EthStrategyGovernorTest is BaseTest {
    DutchAuction dutchAuction;

    uint64 defaultDuration = 1 days;
    uint128 defaultStartPrice = 10_000e6;
    uint128 defaultEndPrice = 3_000e6;
    uint128 defaultAmount = 100e18;
    uint128 defaultProposerAmount = 30_000e18;

    address proposer = address(4);

    function setUp() public virtual override {
        super.setUp();
        vm.label(proposer, "proposer");
        dutchAuction = new DutchAuction(address(ethStrategy), address(usdcToken), address(0));
        vm.prank(initialOwner.addr);
        ethStrategy.transferOwnership(address(ethStrategy));
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(ethStrategy), ethStrategy.GOV_INIT_ADMIN_ROLE());
        ethStrategy.initiateGovernance();
        dutchAuction.grantRoles(admin1.addr, dutchAuction.DA_ADMIN_ROLE());
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        vm.stopPrank();
    }

    function test_constructor_success() public {
        vm.startPrank(initialOwner.addr);
        ethStrategy = new EthStrategy(
            defaultTimelockDelay,
            defaultQuorumPercentage,
            defaultVoteExtension,
            defaultVotingDelay,
            defaultVotingPeriod,
            defaultProposalThreshold
        );
        assertEq(ethStrategy.owner(), initialOwner.addr, "owner role not assigned correctly");
    }

    function test_name_success() public view {
        assertEq(ethStrategy.name(), "EthStrategy", "name not assigned correctly");
    }

    function test_symbol_success() public view {
        assertEq(ethStrategy.symbol(), "ETHXR", "symbol not assigned correctly");
    }

    function test_votingDelay_success() public view {
        assertEq(ethStrategy.votingDelay(), 86400, "votingDelay not assigned correctly");
    }

    function test_votingPeriod_success() public view {
        assertEq(ethStrategy.votingPeriod(), 432000, "votingPeriod not assigned correctly");
    }

    function test_proposalThreshold_success() public view {
        assertEq(ethStrategy.proposalThreshold(), 30_000e18, "proposalThreshold not assigned correctly");
    }

    function test_executionDelay_success() public {
        vm.prank(address(ethStrategy));
        ethStrategy.setExecutionDelay(2 days);
        assertEq(ethStrategy.executionDelay(), 2 days, "executionDelay not assigned correctly");
    }

    function test_executionDelay_revert_InvalidExecutionDelay() public {
        vm.prank(address(ethStrategy));
        vm.expectRevert(EthStrategy.InvalidExecutionDelay.selector);
        ethStrategy.setExecutionDelay(7 days + 1);
        assertEq(ethStrategy.executionDelay(), 1 days, "executionDelay not assigned correctly");
    }

    function test_executionDelay_revert_GovernorOnlyExecutor() public {
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, address(this)));
        ethStrategy.setExecutionDelay(7 days + 1);
        assertEq(ethStrategy.executionDelay(), 1 days, "executionDelay not assigned correctly");
    }

    function test_castVote_success() public {
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);

        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();

        vm.prank(alice);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.Against));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));

        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), true, "alice has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), true, "bob has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(charlie)), true, "charlie has not voted");
        assertEq(
            ethStrategy.proposalSupport(proposalId, address(alice)),
            uint8(GovernorCountingSimple.VoteType.For),
            "alice has voted"
        );
        assertEq(
            ethStrategy.proposalSupport(proposalId, address(bob)),
            uint8(GovernorCountingSimple.VoteType.Against),
            "bob has voted"
        );
        assertEq(
            ethStrategy.proposalSupport(proposalId, address(charlie)),
            uint8(GovernorCountingSimple.VoteType.For),
            "charlie has voted"
        );
    }

    function test_executeOperations_success() public {
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);

        (
            uint256 proposalId,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = setupDefaultDutchAuctionProposal();
        vm.prank(alice);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod());
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Queued), "proposal not queued");
        uint256 eta = ethStrategy.proposalEta(proposalId);
        assertEq(uint48(eta), uint48(block.timestamp + ethStrategy.executionDelay() - 1), "eta not assigned correctly");
        vm.warp(block.timestamp + ethStrategy.executionDelay());
        ethStrategy.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Executed), "proposal not executed");
    }

    function test_executeOperations_revert_GovernorUnmetDelay() public {
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);

        (
            uint256 proposalId,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = setupDefaultDutchAuctionProposal();
        vm.prank(alice);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod());
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Queued), "proposal not queued");
        uint256 eta = ethStrategy.proposalEta(proposalId);
        assertEq(uint48(eta), uint48(block.timestamp + ethStrategy.executionDelay() - 1), "eta not assigned correctly");
        vm.expectRevert(abi.encodeWithSelector(EthStrategy.GovernorUnmetDelay.selector, proposalId, eta));
        ethStrategy.execute(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Queued), "proposal not executed");
    }

    function test_proposalEta_success() public {
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);

        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        vm.prank(alice);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod());
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Queued), "proposal not queued");
        uint256 eta = ethStrategy.proposalEta(proposalId);
        assertEq(uint48(eta), uint48(block.timestamp + ethStrategy.executionDelay() - 1), "eta not assigned correctly");
    }

    function test_proposalEta_lateQuorum_success() public {
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount * 100);

        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        vm.prank(alice);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod() - 1);
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.lateQuorumVoteExtension() + 1);
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Queued), "proposal not queued");
        uint256 eta = ethStrategy.proposalEta(proposalId);
        assertEq(uint48(eta), uint48(block.timestamp + ethStrategy.executionDelay() - 1), "eta not assigned correctly");
    }

    function test_quorum_success() public {
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);

        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        uint256 timepoint = ethStrategy.proposalSnapshot(proposalId);
        uint256 totalSupply = ethStrategy.totalSupply();
        uint256 quorum = totalSupply * defaultQuorumPercentage / 100;
        assertEq(ethStrategy.quorum(timepoint), quorum, "quorum not assigned correctly");
    }

    function test_mint_minter_success() public {
        uint256 role = ethStrategy.MINTER_ROLE();
        vm.prank(address(ethStrategy));
        ethStrategy.grantRoles(bob, role);
        vm.prank(bob);
        ethStrategy.mint(alice, 100e18);
        assertEq(ethStrategy.balanceOf(alice), 100e18, "balance not assigned correctly");
    }

    function test_update_success() public {
        uint256 role = ethStrategy.PAUSER_ROLE();
        vm.prank(address(ethStrategy));
        ethStrategy.grantRoles(bob, role);
        vm.prank(bob);
        ethStrategy.setIsTransferPaused(false);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        vm.prank(alice);
        ethStrategy.transfer(bob, defaultProposerAmount);
        assertEq(ethStrategy.balanceOf(alice), 0, "balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(bob), defaultProposerAmount, "balance not assigned correctly");
    }

    function test_update_paused_mint() public {
        uint256 role = ethStrategy.PAUSER_ROLE();
        vm.prank(address(ethStrategy));
        ethStrategy.grantRoles(bob, role);
        vm.prank(bob);
        ethStrategy.setIsTransferPaused(true);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        assertEq(ethStrategy.balanceOf(alice), defaultProposerAmount, "balance not assigned correctly");
    }

    function test_update_paused_rageQuit() public {
        uint256 role = ethStrategy.PAUSER_ROLE();
        vm.prank(address(ethStrategy));
        ethStrategy.grantRoles(bob, role);
        vm.prank(bob);
        ethStrategy.setIsTransferPaused(true);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        vm.deal(address(ethStrategy), defaultProposerAmount);
        address[] memory assets = new address[](1);
        assets[0] = address(0);
        vm.prank(alice);
        ethStrategy.rageQuit(defaultProposerAmount, 0, assets);
        assertEq(ethStrategy.balanceOf(alice), 0, "balance not assigned correctly");
        assertEq(address(ethStrategy).balance, 0, "ethStrategy balance not assigned correctly");
        assertEq(alice.balance, defaultProposerAmount, "alice balance not assigned correctly");
    }

    function test_update_paused_revert_TransferPaused() public {
        uint256 role = ethStrategy.PAUSER_ROLE();
        vm.prank(address(ethStrategy));
        ethStrategy.grantRoles(bob, role);
        vm.prank(bob);
        ethStrategy.setIsTransferPaused(true);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        vm.expectRevert(EthStrategy.TransferPaused.selector);
        vm.prank(alice);
        ethStrategy.transfer(bob, defaultProposerAmount);
    }

    function test_setIsTransferPaused_success() public {
        uint256 role = ethStrategy.PAUSER_ROLE();
        vm.prank(address(ethStrategy));
        ethStrategy.grantRoles(bob, role);
        vm.prank(bob);
        ethStrategy.setIsTransferPaused(true);
        assertEq(ethStrategy.isTransferPaused(), true, "isTransferPaused not assigned correctly");
    }

    function test_setIsTransferPaused_revert_unauthorized() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        ethStrategy.setIsTransferPaused(true);
    }

    function test_CLOCK_MODE_success() public view {
        assertEq(ethStrategy.CLOCK_MODE(), "mode=timestamp", "CLOCK_MODE not assigned correctly");
    }

    function test_clock_success() public view {
        assertEq(ethStrategy.clock(), block.timestamp, "clock not assigned correctly");
    }

    function test_rageQuit_paused_success() public {
        setIsTransferPaused(true);
        mintAndDelegate(alice, alice, defaultAmount);
        mintAndDelegate(bob, bob, defaultAmount);
        usdcToken.mint(address(ethStrategy), defaultAmount);
        vm.deal(address(ethStrategy), defaultAmount);
        address[] memory assets = new address[](2);
        assets[0] = address(usdcToken);
        assets[1] = address(0);
        vm.prank(alice);
        ethStrategy.rageQuit(defaultAmount, 0, assets);
        assertEq(ethStrategy.balanceOf(alice), 0, "alice's balance not assigned correctly");
        assertEq(usdcToken.balanceOf(alice), defaultAmount / 2, "alice's usdc balance not assigned correctly");
        assertEq(
            usdcToken.balanceOf(address(ethStrategy)),
            defaultAmount / 2,
            "ethStrategy's usdc balance not assigned correctly"
        );
        assertEq(alice.balance, defaultAmount / 2, "alice's eth balance not assigned correctly");
        assertEq(address(ethStrategy).balance, defaultAmount / 2, "ethStrategy's eth balance not assigned correctly");
        assertEq(ethStrategy.balanceOf(bob), defaultAmount, "bob's ethStrategy balance not assigned correctly");
        assertEq(ethStrategy.totalSupply(), defaultAmount, "ethStrategy totalSupply not assigned correctly");
    }

    function test_rageQuit_revert_DuplicateToken_1() public {
        setIsTransferPaused(true);
        mintAndDelegate(alice, alice, defaultAmount);
        mintAndDelegate(bob, bob, defaultAmount);
        usdcToken.mint(address(ethStrategy), defaultAmount);
        vm.deal(address(ethStrategy), defaultAmount);
        address[] memory assets = new address[](2);
        assets[0] = address(usdcToken);
        assets[1] = address(usdcToken);
        vm.expectRevert(EthStrategy.DuplicateToken.selector);
        vm.prank(alice);
        ethStrategy.rageQuit(defaultAmount, 0, assets);
    }

    function test_rageQuit_revert_DuplicateToken_2() public {
        setIsTransferPaused(true);
        mintAndDelegate(alice, alice, defaultAmount);
        mintAndDelegate(bob, bob, defaultAmount);
        usdcToken.mint(address(ethStrategy), defaultAmount);
        vm.deal(address(ethStrategy), defaultAmount);
        address[] memory assets = new address[](3);
        assets[0] = address(usdcToken);
        assets[1] = address(0);
        assets[2] = address(usdcToken);
        vm.expectRevert(EthStrategy.DuplicateToken.selector);
        vm.prank(alice);
        ethStrategy.rageQuit(defaultAmount, 0, assets);
    }

    function test_rageQuit_votedAgainst_1() public {
        setIsTransferPaused(false);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);
        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        vm.prank(alice);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.Against));
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod() + 1);

        usdcToken.mint(address(ethStrategy), defaultAmount);
        vm.deal(address(ethStrategy), defaultAmount);
        address[] memory assets = new address[](2);
        assets[0] = address(usdcToken);
        assets[1] = address(0);
        vm.prank(alice);
        ethStrategy.rageQuit(defaultProposerAmount, proposalId, assets);
        assertEq(ethStrategy.balanceOf(alice), 0, "alice's balance not assigned correctly");
        assertEq(usdcToken.balanceOf(alice), defaultAmount / 4, "alice's usdc balance not assigned correctly");
        assertEq(
            usdcToken.balanceOf(address(ethStrategy)),
            defaultAmount * 3 / 4,
            "ethStrategy's usdc balance not assigned correctly"
        );
        assertEq(alice.balance, defaultAmount / 4, "alice's eth balance not assigned correctly");
        assertEq(
            address(ethStrategy).balance, defaultAmount * 3 / 4, "ethStrategy's eth balance not assigned correctly"
        );
        assertEq(ethStrategy.balanceOf(bob), defaultProposerAmount, "bob's ethStrategy balance not assigned correctly");
        assertEq(
            ethStrategy.balanceOf(charlie),
            defaultProposerAmount,
            "charlie's ethStrategy balance not assigned correctly"
        );
        assertEq(
            ethStrategy.balanceOf(proposer),
            defaultProposerAmount,
            "proposer's ethStrategy balance not assigned correctly"
        );
        assertEq(ethStrategy.totalSupply(), defaultProposerAmount * 3, "ethStrategy totalSupply not assigned correctly");
    }
    /// @dev rageQuit after the execution delay has passed

    function test_rageQuit_succeeded_revert_ProposalNotQueued() public {
        setIsTransferPaused(false);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);
        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        vm.prank(alice);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.Against));
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod() + ethStrategy.executionDelay() + 1);

        usdcToken.mint(address(ethStrategy), defaultAmount);
        vm.deal(address(ethStrategy), defaultAmount);
        address[] memory assets = new address[](2);
        assets[0] = address(usdcToken);
        assets[1] = address(0);
        vm.prank(alice);
        vm.expectRevert(EthStrategy.ProposalNotQueued.selector);
        ethStrategy.rageQuit(defaultProposerAmount, proposalId, assets);
    }

    function test_rageQuit_votedFor_revert_ForVotesCannotRageQuit() public {
        setIsTransferPaused(false);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);
        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        vm.prank(alice);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.Against));
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod() + 1);

        usdcToken.mint(address(ethStrategy), defaultAmount);
        vm.deal(address(ethStrategy), defaultAmount);
        address[] memory assets = new address[](2);
        assets[0] = address(usdcToken);
        assets[1] = address(0);
        vm.prank(bob);
        vm.expectRevert(EthStrategy.ForVotesCannotRageQuit.selector);
        ethStrategy.rageQuit(defaultProposerAmount, proposalId, assets);
        assertEq(ethStrategy.balanceOf(bob), defaultProposerAmount, "bob's balance not assigned correctly");
    }

    function test_rageQuit_votedAbstain_revert_ForVotesCannotRageQuit() public {
        setIsTransferPaused(false);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);
        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        vm.prank(alice);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.Abstain));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod() + 1);

        usdcToken.mint(address(ethStrategy), defaultAmount);
        vm.deal(address(ethStrategy), defaultAmount);
        address[] memory assets = new address[](2);
        assets[0] = address(usdcToken);
        assets[1] = address(0);
        vm.prank(bob);
        vm.expectRevert(EthStrategy.ForVotesCannotRageQuit.selector);
        ethStrategy.rageQuit(defaultProposerAmount, proposalId, assets);
        assertEq(ethStrategy.balanceOf(bob), defaultProposerAmount, "bob's balance not assigned correctly");
    }

    function test_rageQuit_AssetsArrayEmpty() public {
        vm.expectRevert(EthStrategy.AssetsArrayEmpty.selector);
        ethStrategy.rageQuit(defaultProposerAmount, 0, new address[](0));
    }

    function test_rageQuit_pending_revert_ProposalNotQueued() public {
        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        setIsTransferPaused(false);
        vm.expectRevert(EthStrategy.ProposalNotQueued.selector);
        ethStrategy.rageQuit(defaultProposerAmount, proposalId, new address[](2));
    }

    function test_rageQuit_didNotCastVote_success() public {
        setIsTransferPaused(false);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);
        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod());

        usdcToken.mint(address(ethStrategy), defaultAmount);
        vm.deal(address(ethStrategy), defaultAmount);
        address[] memory assets = new address[](2);
        assets[0] = address(usdcToken);
        assets[1] = address(0);
        vm.prank(alice);
        ethStrategy.rageQuit(defaultProposerAmount, proposalId, assets);
        assertEq(ethStrategy.balanceOf(alice), 0, "alice's balance not assigned correctly");
        assertEq(usdcToken.balanceOf(alice), defaultAmount / 4, "alice's usdc balance not assigned correctly");
        assertEq(
            usdcToken.balanceOf(address(ethStrategy)),
            defaultAmount * 3 / 4,
            "ethStrategy's usdc balance not assigned correctly"
        );
        assertEq(alice.balance, defaultAmount / 4, "alice's eth balance not assigned correctly");
        assertEq(
            address(ethStrategy).balance, defaultAmount * 3 / 4, "ethStrategy's eth balance not assigned correctly"
        );
        assertEq(ethStrategy.balanceOf(bob), defaultProposerAmount, "bob's ethStrategy balance not assigned correctly");
        assertEq(
            ethStrategy.balanceOf(charlie),
            defaultProposerAmount,
            "charlie's ethStrategy balance not assigned correctly"
        );
        assertEq(
            ethStrategy.balanceOf(proposer),
            defaultProposerAmount,
            "proposer's ethStrategy balance not assigned correctly"
        );
        assertEq(ethStrategy.totalSupply(), defaultProposerAmount * 3, "ethStrategy totalSupply not assigned correctly");
    }

    function test_proposal_success() public {
        vm.startPrank(address(dutchAuction));
        ethStrategy.mint(alice, defaultProposerAmount);
        ethStrategy.mint(bob, defaultProposerAmount);
        ethStrategy.mint(charlie, defaultProposerAmount);
        vm.stopPrank();
        vm.prank(alice);
        ethStrategy.delegate(alice);
        vm.prank(bob);
        ethStrategy.delegate(bob);
        vm.prank(charlie);
        ethStrategy.delegate(charlie);

        address[] memory targets = new address[](1);
        targets[0] = address(dutchAuction);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            DutchAuction.startAuction.selector, 0, defaultDuration, defaultStartPrice, defaultEndPrice, defaultAmount
        );
        string memory description = "test";
        vm.warp(block.timestamp + 1); // make delegated votes active
        uint256 proposalId = ethStrategy.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        vm.startPrank(charlie);
        vm.expectEmit(address(ethStrategy));
        emit IGovernor.ProposalCreated(
            proposalId,
            charlie,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            block.timestamp + ethStrategy.votingDelay(),
            block.timestamp + ethStrategy.votingPeriod() + ethStrategy.votingDelay(),
            description
        );
        ethStrategy.propose(targets, values, calldatas, description);
        vm.stopPrank();
        assertEq(
            uint256(ethStrategy.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "proposal not pending"
        );
        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), false, "alice has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), false, "bob has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(charlie)), false, "charlie has not voted");

        vm.warp(block.timestamp + ethStrategy.votingDelay() + 1);

        vm.prank(alice);
        ethStrategy.castVote(proposalId, 1);
        vm.prank(bob);
        ethStrategy.castVote(proposalId, 0);
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, 1);

        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), true, "alice has voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), true, "bob has voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(charlie)), true, "charlie has voted");
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Active), "proposal not active");
        vm.warp(block.timestamp + ethStrategy.votingPeriod() + 1);
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Queued), "proposal not succeeded");
        // ethStrategy.queue(targets, values, calldatas, keccak256(bytes(description)));
        vm.warp(block.timestamp + ethStrategy.executionDelay() - 1);
        DutchAuction.Auction memory auction = DutchAuction.Auction({
            startTime: uint64(block.timestamp),
            duration: defaultDuration,
            startPrice: defaultStartPrice,
            endPrice: defaultEndPrice,
            amount: defaultAmount
        });
        bytes32 descriptionHash = keccak256(bytes(description));
        bytes32 salt = bytes20(address(ethStrategy)) ^ descriptionHash;
        // bytes32 id = ethStrategy.hashOperationBatch(targets, values, calldatas, 0, salt);
        vm.expectEmit();
        emit DutchAuction.AuctionStarted(auction);
        // vm.expectEmit();
        // emit TimelockController.CallExecuted(id, 0, targets[0], values[0], calldatas[0]);
        vm.expectEmit();
        emit IGovernor.ProposalExecuted(proposalId);
        ethStrategy.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function test_proposal_revert_GovernanceNotInitiated() public {
        vm.startPrank(initialOwner.addr);
        ethStrategy = new EthStrategy(
            defaultTimelockDelay,
            defaultQuorumPercentage,
            defaultVoteExtension,
            defaultVotingDelay,
            defaultVotingPeriod,
            defaultProposalThreshold
        );
        dutchAuction = new DutchAuction(address(ethStrategy), address(usdcToken), address(0));
        ethStrategy.transferOwnership(address(ethStrategy));
        vm.stopPrank();
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(ethStrategy), ethStrategy.GOV_INIT_ADMIN_ROLE());
        dutchAuction.grantRoles(admin1.addr, dutchAuction.DA_ADMIN_ROLE());
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        vm.stopPrank();

        vm.startPrank(address(dutchAuction));
        ethStrategy.mint(alice, defaultProposerAmount);
        ethStrategy.mint(bob, defaultProposerAmount);
        ethStrategy.mint(charlie, defaultProposerAmount);
        vm.stopPrank();
        vm.prank(alice);
        ethStrategy.delegate(alice);
        vm.prank(bob);
        ethStrategy.delegate(bob);
        vm.prank(charlie);
        ethStrategy.delegate(charlie);

        address[] memory targets = new address[](1);
        targets[0] = address(dutchAuction);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            DutchAuction.startAuction.selector, 0, defaultDuration, defaultStartPrice, defaultEndPrice, defaultAmount
        );
        string memory description = "test";
        vm.warp(block.timestamp + 1); // make delegated votes active
        vm.startPrank(charlie);
        vm.expectRevert(EthStrategy.GovernanceNotInitiated.selector);
        ethStrategy.propose(targets, values, calldatas, description);
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
        dutchAuction = new DutchAuction(address(ethStrategy), address(usdcToken), address(0));
        ethStrategy.transferOwnership(address(ethStrategy));
        vm.stopPrank();
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(ethStrategy), ethStrategy.GOV_INIT_ADMIN_ROLE());
        dutchAuction.grantRoles(admin1.addr, dutchAuction.DA_ADMIN_ROLE());
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        ethStrategy.initiateGovernance();
        vm.stopPrank();

        assertEq(ethStrategy.governanceInitiated(), true, "governance not initiated");
    }

    function test_initiateGovernance_revert_GovernanceAlreadyInitiated() public {
        vm.startPrank(initialOwner.addr);
        ethStrategy = new EthStrategy(
            defaultTimelockDelay,
            defaultQuorumPercentage,
            defaultVoteExtension,
            defaultVotingDelay,
            defaultVotingPeriod,
            defaultProposalThreshold
        );
        dutchAuction = new DutchAuction(address(ethStrategy), address(usdcToken), address(0));
        ethStrategy.transferOwnership(address(ethStrategy));
        vm.stopPrank();
        vm.startPrank(address(ethStrategy));
        ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(ethStrategy), ethStrategy.GOV_INIT_ADMIN_ROLE());
        dutchAuction.grantRoles(admin1.addr, dutchAuction.DA_ADMIN_ROLE());
        dutchAuction.grantRoles(admin2.addr, dutchAuction.DA_ADMIN_ROLE());
        ethStrategy.initiateGovernance();
        vm.expectRevert(EthStrategy.GovernanceAlreadyInitiated.selector);
        ethStrategy.initiateGovernance();
        vm.stopPrank();

        assertEq(ethStrategy.governanceInitiated(), true, "governance not initiated");
    }

    function test_proposal_didNotReachQuorum() public {
        vm.startPrank(address(dutchAuction));
        ethStrategy.mint(alice, defaultProposerAmount * 94);
        ethStrategy.mint(bob, defaultProposerAmount * 3);
        ethStrategy.mint(charlie, defaultProposerAmount * 3);
        vm.stopPrank();
        vm.prank(alice);
        ethStrategy.delegate(alice);
        vm.prank(bob);
        ethStrategy.delegate(bob);
        vm.prank(charlie);
        ethStrategy.delegate(charlie);

        address[] memory targets = new address[](1);
        targets[0] = address(dutchAuction);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            DutchAuction.startAuction.selector, 0, defaultDuration, defaultStartPrice, defaultEndPrice, defaultAmount
        );
        string memory description = "test";
        vm.warp(block.timestamp + 1); // make delegated votes active
        uint256 proposalId = ethStrategy.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        vm.startPrank(charlie);
        vm.expectEmit(address(ethStrategy));
        emit IGovernor.ProposalCreated(
            proposalId,
            charlie,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            block.timestamp + ethStrategy.votingDelay(),
            block.timestamp + ethStrategy.votingPeriod() + ethStrategy.votingDelay(),
            description
        );
        ethStrategy.propose(targets, values, calldatas, description);
        vm.stopPrank();
        assertEq(
            uint256(ethStrategy.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "proposal not pending"
        );
        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), false, "alice has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), false, "bob has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(charlie)), false, "charlie has not voted");

        vm.warp(block.timestamp + ethStrategy.votingDelay() + 1);

        vm.prank(bob);
        ethStrategy.castVote(proposalId, 1);

        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), false, "alice has voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), true, "bob has voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(charlie)), false, "charlie has voted");
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Active), "proposal not active");
        vm.warp(block.timestamp + ethStrategy.votingPeriod() + 1);
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Defeated), "proposal not defeated");

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorUnexpectedProposalState.selector, proposalId, 3, 48));
        ethStrategy.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function test_proposal_defeated() public {
        mintAndDelegate(alice, alice, defaultProposerAmount * 97);
        mintAndDelegate(bob, bob, defaultProposerAmount * 3);
        mintAndDelegate(charlie, charlie, defaultProposerAmount * 3);
        (
            uint256 proposalId,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = setupDefaultDutchAuctionProposal();

        vm.prank(alice);
        ethStrategy.castVote(proposalId, 0);

        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), true, "alice has voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), false, "bob has voted");
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Active), "proposal not active");
        vm.warp(block.timestamp + ethStrategy.votingPeriod() + 1);
        assertEq(uint8(ethStrategy.state(proposalId)), uint8(IGovernor.ProposalState.Defeated), "proposal not defeated");

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorUnexpectedProposalState.selector, proposalId, 3, 48));
        ethStrategy.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    function test_rageQuit_revert_NoTransfersOccured() public {
        uint256 role = ethStrategy.PAUSER_ROLE();
        vm.prank(address(ethStrategy));
        ethStrategy.grantRoles(bob, role);
        vm.prank(bob);
        ethStrategy.setIsTransferPaused(true);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        address[] memory assets = new address[](1);
        assets[0] = address(0);
        vm.expectRevert(EthStrategy.NoTransfersOccured.selector);
        vm.prank(alice);
        ethStrategy.rageQuit(defaultProposerAmount, 0, assets);
        assertEq(ethStrategy.balanceOf(alice), defaultProposerAmount, "balance not assigned correctly");
    }

    function test_rageQuit_revert_AmountExceedsPastBalance() public {
        setIsTransferPaused(false);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);
        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod());

        vm.prank(alice);
        vm.expectRevert(EthStrategy.AmountExceedsPastBalance.selector);
        ethStrategy.rageQuit(defaultProposerAmount + 1, proposalId, new address[](1));
    }

    function test_rageQuit_revert_GovernanceNotAllowed() public {
        setIsTransferPaused(true);
        mintAndDelegate(address(ethStrategy), address(ethStrategy), defaultAmount);
        usdcToken.mint(address(ethStrategy), defaultAmount);
        vm.deal(address(ethStrategy), defaultAmount);
        address[] memory assets = new address[](2);
        assets[0] = address(usdcToken);
        assets[1] = address(0);
        vm.prank(address(ethStrategy));
        vm.expectRevert(EthStrategy.GovernanceNotAllowed.selector);
        ethStrategy.rageQuit(defaultAmount, 0, assets);
    }

    function test_proposalDeadline_success() public {
        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        assertEq(
            ethStrategy.proposalDeadline(proposalId),
            block.timestamp + ethStrategy.votingPeriod() - 1,
            "proposal deadline not assigned correctly"
        );
    }

    function test_rageQuit_revert_ERC20InsufficientBalance() public {
        setIsTransferPaused(false);
        mintAndDelegate(alice, alice, defaultProposerAmount);
        mintAndDelegate(bob, bob, defaultProposerAmount);
        mintAndDelegate(charlie, charlie, defaultProposerAmount);
        (uint256 proposalId,,,,) = setupDefaultDutchAuctionProposal();
        vm.prank(bob);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.prank(charlie);
        ethStrategy.castVote(proposalId, uint8(GovernorCountingSimple.VoteType.For));
        vm.warp(block.timestamp + ethStrategy.votingPeriod());

        vm.startPrank(alice);
        ethStrategy.transfer(bob, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, defaultProposerAmount - 1, defaultProposerAmount
            )
        );
        ethStrategy.rageQuit(defaultProposerAmount, proposalId, new address[](1));
    }

    function setupDefaultDutchAuctionProposal()
        public
        returns (
            uint256 proposalId,
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        )
    {
        mintAndDelegate(proposer, proposer, defaultProposerAmount);
        vm.warp(block.timestamp + 1);

        targets = new address[](1);
        targets[0] = address(dutchAuction);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            DutchAuction.startAuction.selector, 0, defaultDuration, defaultStartPrice, defaultEndPrice, defaultAmount
        );
        description = "test";
        // make delegated votes active
        proposalId = ethStrategy.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        vm.startPrank(proposer);
        vm.expectEmit(address(ethStrategy));
        emit IGovernor.ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            new string[](targets.length),
            calldatas,
            block.timestamp + ethStrategy.votingDelay(),
            block.timestamp + ethStrategy.votingPeriod() + ethStrategy.votingDelay(),
            description
        );
        ethStrategy.propose(targets, values, calldatas, description);
        vm.stopPrank();
        assertEq(
            uint256(ethStrategy.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "proposal not pending"
        );
        assertEq(ethStrategy.proposalNeedsQueuing(proposalId), false, "proposal needs queuing");
        assertEq(ethStrategy.hasVoted(proposalId, address(alice)), false, "alice has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(bob)), false, "bob has not voted");
        assertEq(ethStrategy.hasVoted(proposalId, address(charlie)), false, "charlie has not voted");

        vm.warp(block.timestamp + ethStrategy.votingDelay() + 1);

        return (proposalId, targets, values, calldatas, description);
    }

    function mintAndDelegate(address to, address delegate, uint256 amount) public {
        address minter = address(5);
        uint256 role = ethStrategy.MINTER_ROLE();
        vm.prank(address(ethStrategy));
        ethStrategy.grantRoles(minter, role);
        vm.prank(minter);
        ethStrategy.mint(to, amount);
        vm.prank(to);
        ethStrategy.delegate(delegate);
    }

    function setIsTransferPaused(bool isTransferPaused) public {
        uint256 role = ethStrategy.PAUSER_ROLE();
        vm.prank(address(ethStrategy));
        ethStrategy.grantRoles(charlie, role);
        vm.prank(charlie);
        ethStrategy.setIsTransferPaused(isTransferPaused);
    }
}
