// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {IEthStrategy} from "./EthStrategy.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract NavOptions is OwnableRoles, ERC20 {
    struct NavValue {
        address token;
        uint256 value;
    }

    address[] internal navTokens;
    /// @dev The role of the nav admin can add and remove nav tokens
    uint256 public constant NAV_ADMIN_ROLE = uint256(keccak256("NAV_ADMIN_ROLE"));
    /// @dev The role for the minter can mint options
    uint256 public constant MINTER_ROLE = uint256(keccak256("MINTER_ROLE"));

    address public immutable ETH_STRATEGY;

    error AmountIsZero();

    constructor(address _ethStrategy) {
        _initializeOwner(_ethStrategy);
        ETH_STRATEGY = _ethStrategy;
    }

    function name() public view virtual override returns (string memory) {
        return "EthStrategy Options";
    }

    function symbol() public view virtual override returns (string memory) {
        return "oETHxr";
    }

    function mint(address _to, uint256 _amount) external onlyRoles(MINTER_ROLE) {
        _mint(_to, _amount);
    }

    function redeem(uint256 _amount) external payable {
        IEthStrategy ethStrategy = IEthStrategy(ETH_STRATEGY);
        NavValue[] memory navValues = _getNavValue(_amount);
        _burn(msg.sender, _amount);
        uint256 i = 0;
        uint256 len = navValues.length;
        for (; i < len;) {
            NavValue memory navValue = navValues[i];
            if (navValue.token == address(0)) {
                SafeTransferLib.safeTransferETH(address(ethStrategy), navValue.value);
                if (navValue.value < msg.value) {
                    SafeTransferLib.safeTransferETH(msg.sender, msg.value - navValue.value);
                }
            } else {
                SafeTransferLib.safeTransferFrom(navValue.token, msg.sender, address(ethStrategy), navValue.value);
            }
            unchecked {
                ++i;
            }
        }
        ethStrategy.mint(msg.sender, _amount);
    }

    function getNavValue(uint256 amount) external view returns (NavValue[] memory navValues) {
        return _getNavValue(amount);
    }

    function addNavToken(address _navToken) public onlyOwnerOrRoles(NAV_ADMIN_ROLE) {
        navTokens.push(_navToken);
    }

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

    function _getNavValue(uint256 _amount) internal view returns (NavValue[] memory navValues) {
        if (_amount == 0) {
            revert AmountIsZero();
        }
        address _owner = ETH_STRATEGY;
        uint256 totalSupply = IERC20(_owner).totalSupply();
        navValues = new NavValue[](navTokens.length + 1);
        uint256 i = 0;
        uint256 newLen = 0;
        uint256 len = navTokens.length;
        for (; i < len;) {
            address navToken = navTokens[i];
            bytes32 codeHash;
            assembly ("memory-safe") {
                codeHash := extcodehash(navToken)
            }
            if (codeHash != bytes32(0)) {
                try IERC20(navToken).balanceOf(_owner) returns (uint256 _balance) {
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
                } catch {}
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
        assembly ("memory-safe") {
            mstore(navValues, newLen)
        }
    }

    function getNavTokens() external view returns (address[] memory) {
        return navTokens;
    }
}
