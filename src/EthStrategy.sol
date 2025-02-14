// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {IGovernor, Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorPreventLateQuorum} from "@openzeppelin/contracts/governance/extensions/GovernorPreventLateQuorum.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Votes, VotesExtended} from "@openzeppelin/contracts/governance/utils/VotesExtended.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ERC20, ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Votes, VotesExtended} from "@openzeppelin/contracts/governance/utils/VotesExtended.sol";
import {TReentrancyGuard} from "lib/TReentrancyGuard/src/TReentrancyGuard.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";

interface IEthStrategy {
    function decimals() external view returns (uint8);
    function mint(address _to, uint256 _amount) external;
    function initiateGovernance() external;
}

contract EthStrategy is
    ERC20Votes,
    VotesExtended,
    Governor,
    GovernorVotes,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotesQuorumFraction,
    GovernorPreventLateQuorum,
    OwnableRoles,
    TReentrancyGuard
{
    /// @dev The error for when a transfer is attempted but transfers are paused (minting/burning is still allowed)
    error TransferPaused();
    /// @dev The error for when a user attempts a rageQuit but the proposal is not in teh queued state
    error ProposalNotQueued();
    /// @dev The error for when a user voted for a proposal and is attempting to rageQuit
    error ForVotesCannotRageQuit();
    /// @dev The error for when the amount of shares to burn in a rageQuitexceeds the user's balance when they cast their votes
    error AmountExceedsPastBalance();
    /// @dev The rageQuit error for when the assets array is empty
    error AssetsArrayEmpty();
    /// @dev The error for when a proposal is not met with the delay
    error GovernorUnmetDelay(uint256 proposalId, uint48 etaSeconds);
    /// @dev The error for when a governance call is to a restricted method
    error GovernanceNotAllowed();
    /// @dev The error for when the execution delay is invalid
    error InvalidExecutionDelay();
    /// @dev The error for when no transfers occured during a rageQuit
    error NoTransfersOccured();
    /// @dev The event for when the execution delay is set

    event ExecutionDelaySet(uint256 oldExecutionDelay, uint256 newExecutionDelay);
    /// @dev The event for when governance is not initiated
    event GovernanceNotInitiated();
    /// @dev The event for when governance is already initiated
    event GovernanceAlreadyInitiated();

    uint256 public executionDelay;

    /// @dev The role for the minter is able to mint unlimited tokens
    uint256 public constant MINTER_ROLE = uint256(keccak256("MINTER_ROLE"));
    /// @dev The role of the pauser can pause transfers of tokens
    uint256 public constant PAUSER_ROLE = uint256(keccak256("PAUSER_ROLE"));
    /// @dev The role of the governance initiator
    uint256 public constant GOV_INIT_ADMIN_ROLE = uint256(keccak256("GOV_INIT_ADMIN_ROLE"));
    /// @dev The transfer pause status, minting is still allowed
    bool public isTransferPaused = true;
    /// @dev The status of the governance initiation
    bool public governanceInitiated = false;
    /// @dev The mapping of proposal ids to the support of the proposal
    mapping(uint256 => mapping(address => uint8)) public proposalSupport;

    /// @notice The constructor for EthStrategy
    /// @param _executionDelay The execution delay for the governor (in seconds) the time after a proposal succeeds before it can be executed
    /// @param _quorumPercentage The quorum percentage for the governor (0-100) the minimum percentage of votes required to reach quorum for a proposal to succeed
    /// @param _voteExtension The vote extension for the governor when a late quorum is reached, the proposal will be queued for an additional _voteExtension seconds
    /// @param _initialVotingDelay The initial voting delay for the governor
    /// @param _initialVotingPeriod The initial voting period for the governor
    /// @param _initialProposalThreshold The initial proposal threshold for the governor
    constructor(
        uint32 _executionDelay,
        uint256 _quorumPercentage,
        uint48 _voteExtension,
        uint48 _initialVotingDelay,
        uint32 _initialVotingPeriod,
        uint256 _initialProposalThreshold
    )
        ERC20("EthStrategy", "ETHXR")
        Governor("EthStrategy")
        GovernorVotes(this)
        GovernorSettings(_initialVotingDelay, _initialVotingPeriod, _initialProposalThreshold)
        GovernorVotesQuorumFraction(_quorumPercentage)
        GovernorPreventLateQuorum(_voteExtension)
    {
        _setExecutionDelay(_executionDelay);
        _initializeOwner(msg.sender);
    }
    /// @inheritdoc ERC20

    function name() public pure virtual override(ERC20, Governor) returns (string memory) {
        return "EthStrategy";
    }
    /// @inheritdoc ERC20

    function symbol() public pure virtual override returns (string memory) {
        return "ETHXR";
    }
    /// @inheritdoc GovernorSettings

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.votingDelay();
    }
    /// @inheritdoc GovernorSettings

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.votingPeriod();
    }
    /// @inheritdoc GovernorSettings

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.proposalThreshold();
    }
    /// @notice A function to set the execution delay for the governor
    /// @param newExecutionDelay The new execution delay for the governor

    function setExecutionDelay(uint32 newExecutionDelay) public virtual onlyGovernance {
        _setExecutionDelay(newExecutionDelay);
    }
    /// @dev A function to set the execution delay for the governor
    /// @param newExecutionDelay The new execution delay for the governor

    function _setExecutionDelay(uint256 newExecutionDelay) internal virtual {
        if (newExecutionDelay > 7 days) {
            assembly {
                mstore(0x00, 0xf8b9a2e3) // `InvalidExecutionDelay()`.
                revert(0x1c, 0x04)
            }
        }
        emit ExecutionDelaySet(executionDelay, newExecutionDelay);
        executionDelay = newExecutionDelay;
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256) {
        if (!governanceInitiated) {
            assembly {
                mstore(0x00, 0x793725b6) // `GovernanceNotInitiated()`.
                revert(0x1c, 0x04)
            }
        }
        return super.propose(targets, values, calldatas, description);
    }
    /// @inheritdoc Governor
    /// @dev This function is overridden to store the vote type for each proposal (used later for rageQuit)

    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        virtual
        override
        returns (uint256)
    {
        proposalSupport[proposalId][account] = support;
        return super._castVote(proposalId, account, support, reason, params);
    }
    /// @inheritdoc Governor
    /// @dev This function

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual override {
        uint48 etaSeconds = uint48(proposalEta(proposalId));
        if (block.timestamp < etaSeconds) {
            revert GovernorUnmetDelay(proposalId, etaSeconds);
        }
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }
    /// @inheritdoc Governor
    /// @dev ---

    function proposalEta(uint256 proposalId) public view virtual override returns (uint256) {
        return proposalDeadline(proposalId) + executionDelay;
    }
    /// @inheritdoc GovernorVotesQuorumFraction

    function quorum(uint256 timepoint) public view override(GovernorVotesQuorumFraction, Governor) returns (uint256) {
        return GovernorVotesQuorumFraction.quorum(timepoint);
    }
    /// @notice A function to mint tokens, only callable by the owner or minter role
    /// @param _to The address to mint the tokens to
    /// @param _amount The amount of tokens to mint

    function mint(address _to, uint256 _amount) public onlyRoles(MINTER_ROLE) {
        _mint(_to, _amount);
    }
    /// @inheritdoc ERC20
    /// @notice Function is overiddent to check if transfers are paused
    /// @notice When transfers are paused, minting/burning is still allowed

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && isTransferPaused) {
            assembly {
                mstore(0x00, 0xcd1fda9f) // `TransferPaused()`.
                revert(0x1c, 0x04)
            }
        }
        super._update(from, to, value);
    }
    /// @notice A function to pause transfers of tokens, only callable by the owner or the pauser role
    /// @notice When transfers are paused, minting/burning is still allowed
    /// @param _isTransferPaused The new transfer pause status

    function setIsTransferPaused(bool _isTransferPaused) public onlyRoles(PAUSER_ROLE) {
        isTransferPaused = _isTransferPaused;
    }
    /// @inheritdoc Governor

    function CLOCK_MODE() public view virtual override(Governor, GovernorVotes, Votes) returns (string memory) {
        return "mode=timestamp";
    }
    /// @inheritdoc Governor

    function clock() public view virtual override(Governor, GovernorVotes, Votes) returns (uint48 result) {
        return uint48(block.timestamp);
    }
    /// @notice A function designed to allow a user to burn their shares and redeem their assets under the conditions that their delegate did not vote for the proposal or transfers are paused
    /// @param amount The amount of shares to burn, assets will be redeemed proportionally to the amount of shares burned
    /// @param proposalId The proposalId of the proposal that the user's delegate voted Against, or did not cast a vote
    /// @param assets An array of assets to redeem from the contract

    function rageQuit(uint256 amount, uint256 proposalId, address[] calldata assets)
        external
        nonreentrant
        notGovernance
    {
        // @dev prevents the user from rage quitting without assets
        if (assets.length == 0) {
            assembly {
                mstore(0x00, 0x6ac3c7ef) // `AssetsArrayEmpty()`.
                revert(0x1c, 0x04)
            }
        }
        // @dev if transfers are not paused, the user can bypass the voting requirements to rageQuit
        if (!isTransferPaused) {
            // @dev if the proposal is not queued, the user cannot rageQuit
            if (state(proposalId) != IGovernor.ProposalState.Queued) {
                assembly {
                    mstore(0x00, 0x599fb1a3) // `ProposalNotQueued()`.
                    revert(0x1c, 0x04)
                }
            }
            // @dev the timepoint of the proposal is the start of the voting period
            uint256 timepoint = proposalSnapshot(proposalId);
            // @dev the delegate is the address that the user delegated their votes to
            address delegate = getPastDelegate(msg.sender, timepoint);
            // @dev it is acceptable if delegate is address(0), then the user has not delegated their votes to rageQuit
            if (proposalSupport[proposalId][delegate] != uint8(GovernorCountingSimple.VoteType.Against)) {
                assembly {
                    mstore(0x00, 0x08e127e6) // `ForVotesCannotRageQuit()`.
                    revert(0x1c, 0x04)
                }
            }
            // @dev the user's balance at the timepoint of the proposal must be greater than or equal to the amount of shares they are attempting to burn
            if (getPastBalanceOf(msg.sender, timepoint) < amount) {
                assembly {
                    mstore(0x00, 0x811fb878) // `AmountExceedsPastBalance()`.
                    revert(0x1c, 0x04)
                }
            }
        }
        // @dev caching the totalSupply before _burn changes the value
        uint256 _totalSupply = totalSupply();
        // @dev the user's balance is burned
        _burn(msg.sender, amount);
        // @dev the user's assets are redeemed
        uint256 i = 0;
        uint256 len = assets.length;
        bool transferOcurred = false;
        for (; i < len;) {
            address asset = assets[i];
            uint256 _balance;
            if (asset == address(0)) {
                _balance = address(this).balance;
            } else {
                _balance = IERC20(asset).balanceOf(address(this));
            }
            unchecked {
                _balance = (_balance * amount) / _totalSupply;
            }
            if (_balance != 0) {
                if (asset == address(0)) {
                    SafeTransferLib.safeTransferETH(msg.sender, _balance);
                    transferOcurred = true;
                } else {
                    SafeTransferLib.safeTransfer(asset, msg.sender, _balance);
                    transferOcurred = true;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (!transferOcurred) {
            assembly {
                mstore(0x00, 0x0f06c1fc) // `NoTransfersOccured()`.
                revert(0x1c, 0x04)
            }
        }
    }

    modifier notGovernance() {
        if (msg.sender == address(this)) {
            assembly {
                mstore(0x00, 0x7c95ff76) // `GovernanceNotAllowed()`.
                revert(0x1c, 0x04)
            }
        }
        _;
    }
    /// @notice A function to initiate the governance of the contract

    function initiateGovernance() public onlyRoles(GOV_INIT_ADMIN_ROLE) {
        if (governanceInitiated) {
            assembly {
                mstore(0x00, 0x6ef777ac) // `GovernanceAlreadyInitiated()`.
                revert(0x1c, 0x04)
            }
        }
        governanceInitiated = true;
        isTransferPaused = false;
    }
    /// @inheritdoc VotesExtended

    function _delegate(address account, address delegatee) internal virtual override(VotesExtended, Votes) {
        VotesExtended._delegate(account, delegatee);
    }
    /// @inheritdoc VotesExtended

    function _transferVotingUnits(address from, address to, uint256 value) internal override(VotesExtended, Votes) {
        VotesExtended._transferVotingUnits(from, to, value);
    }
    /// @inheritdoc GovernorPreventLateQuorum

    function _tallyUpdated(uint256 proposalId) internal virtual override(GovernorPreventLateQuorum, Governor) {
        GovernorPreventLateQuorum._tallyUpdated(proposalId);
    }
    /// @inheritdoc GovernorPreventLateQuorum

    function proposalDeadline(uint256 proposalId)
        public
        view
        virtual
        override(GovernorPreventLateQuorum, Governor)
        returns (uint256)
    {
        return GovernorPreventLateQuorum.proposalDeadline(proposalId);
    }
}
