// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./interfaces/IEthStrategy.sol";
import {TReentrancyGuard} from "../lib/TReentrancyGuard/src/TReentrancyGuard.sol";

contract NavOptions is OwnableRoles, ERC20, TReentrancyGuard {
    struct NavValue {
        address token;
        uint256 value;
    }

    /// @dev The array of nav tokens, must be updated each time EthStrategy obtains a new asset
    address[] internal navTokens;
    /// @dev The role of the nav admin can add and remove nav tokens
    uint256 public constant NAV_ADMIN_ROLE = uint256(keccak256("NAV_ADMIN_ROLE"));
    /// @dev The role for the minter can mint options (oETHxr)
    uint256 public constant MINTER_ROLE = uint256(keccak256("MINTER_ROLE"));
    /// @dev The address of the EthStrategy contract
    address public immutable ETH_STRATEGY;

    /// @dev The error for when the amount provided by the redeemer is zero
    error AmountIsZero();
    /// @dev The error for when the nav token is address(0), prevents a double ETH payment footgun
    error InvalidNavToken();

    /// @notice The constructor for NavOptions
    /// @param _ethStrategy The address of the EthStrategy contract
    constructor(address _ethStrategy) {
        _initializeOwner(_ethStrategy);
        ETH_STRATEGY = _ethStrategy;
    }

    /// @inheritdoc ERC20
    function name() public view virtual override returns (string memory) {
        return "EthStrategy Options";
    }

    /// @inheritdoc ERC20
    function symbol() public view virtual override returns (string memory) {
        return "oETHxr";
    }

    /// @notice A function to mint options (oETHxr), only callable by the minter role
    /// @param _to The address to mint the options to
    /// @param _amount The amount of options to mint
    function mint(address _to, uint256 _amount) external onlyRoles(MINTER_ROLE) {
        _mint(_to, _amount);
    }

    /// @notice A function to redeem options (oETHxr), oETHxr is burned and the redeemer pays a proportional value of navTokens to the EthStrategy contract and receives ETHXR
    /// @param _amount The amount of options to redeem
    function redeem(uint256 _amount) external payable nonreentrant {
        IEthStrategy ethStrategy = IEthStrategy(ETH_STRATEGY);
        NavValue[] memory navValues = _getNavValue(_amount);
        _burn(msg.sender, _amount);
        uint256 i = 0;
        uint256 len = navValues.length;
        uint256 refund = 0;
        for (; i < len;) {
            NavValue memory navValue = navValues[i];
            if (navValue.token == address(0)) {
                SafeTransferLib.safeTransferETH(address(ethStrategy), navValue.value);
                if (navValue.value < msg.value) {
                    refund += msg.value - navValue.value;
                }
            } else {
                SafeTransferLib.safeTransferFrom(navValue.token, msg.sender, address(ethStrategy), navValue.value);
            }
            unchecked {
                ++i;
            }
        }
        ethStrategy.mint(msg.sender, _amount);
        if (refund > 0) {
            SafeTransferLib.safeTransferETH(msg.sender, refund);
        }
    }

    /// @notice A function to get the nav value for option redemption
    /// @param amount The amount of options to get the nav value of
    /// @return navValues The nav value of the options
    function getNavValue(uint256 amount) external view returns (NavValue[] memory navValues) {
        return _getNavValue(amount);
    }

    /// @notice A function to add a nav token to the navTokens array only callable by owner or NAV_ADMIN_ROLE
    /// @param _navToken The address of the nav token to add
    function addNavToken(address _navToken) public onlyOwnerOrRoles(NAV_ADMIN_ROLE) {
        if (_navToken == address(0)) {
            revert InvalidNavToken();
        }
        navTokens.push(_navToken);
    }

    /// @notice A function to remove a nav token from the navTokens array only callable by owner or NAV_ADMIN_ROLE
    /// @param _navToken The address of the nav token to remove
    function removeNavToken(address _navToken) public onlyOwnerOrRoles(NAV_ADMIN_ROLE) {
        uint256 i = 0;
        uint256 len = navTokens.length;
        for (; i < len;) {
            if (navTokens[i] == _navToken) {
                navTokens[i] = navTokens[len - 1];
                navTokens.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice An internal function to get the nav value for option redemption
    /// @param _amount The amount of options to get the nav value of
    /// @return navValues The nav value of the options
    function _getNavValue(uint256 _amount) internal view returns (NavValue[] memory navValues) {
        if (_amount == 0) {
            revert AmountIsZero();
        }
        /// @dev cache the owner to save gas
        address _owner = ETH_STRATEGY;
        /// @dev get the total supply of EthStrategy tokens
        uint256 totalSupply = ERC20(_owner).totalSupply();
        /// @dev initialize the navValues array with an extra element (for ETH)
        navValues = new NavValue[](navTokens.length + 1);
        uint256 i = 0;
        uint256 newLen = 0;
        uint256 len = navTokens.length;
        for (; i < len;) {
            address navToken = navTokens[i];
            bytes32 codeHash;
            assembly {
                codeHash := extcodehash(navToken)
            }
            if (codeHash != bytes32(0)) {
                uint256 _balance = ERC20(navToken).balanceOf(_owner);
                if (_balance != 0) {
                    uint256 proportion = (_balance * _amount) / totalSupply;
                    if (proportion == 0) {
                        proportion = 1;
                    }
                    navValues[newLen] = NavValue({token: navToken, value: proportion});
                    unchecked {
                        ++newLen;
                    }
                }
            }
            unchecked {
                ++i;
            }
        }
        uint256 balance = _owner.balance;
        if (balance > 0) {
            uint256 proportion = (balance * _amount) / totalSupply;
            if (proportion == 0) {
                proportion = 1;
            }
            navValues[newLen] = NavValue({token: address(0), value: proportion});
            unchecked {
                ++newLen;
            }
        }
        assembly {
            mstore(navValues, newLen)
        }
    }

    /// @notice A function to get the nav tokens
    /// @return navTokens The array of nav tokens
    function getNavTokens() external view returns (address[] memory) {
        return navTokens;
    }
}
