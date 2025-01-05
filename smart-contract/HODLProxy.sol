// SPDX-License-Identifier: MIT

//  __    __    ______    _____      __
// |  |  |  |  /  __  \  |      \   |  |
// |  |__|  | |  |  |  | |   _   \  |  |
// |   __   | |  |  |  | |  |_)   | |  |
// |  |  |  | |  `--'  | |       /  |  |____
// |__|  |__|  \______/  |_____ /   |_______|
//                 HODL TOKEN

// HODL Token Transparent Upgradeable Proxy Contract:
// Implements a transparent upgradeable proxy allowing secure, controlled upgrades
// of the HODL token contract logic. This contract restricts access to administrative
// functions, preventing unauthorized upgrades and enforcing structured ownership.

pragma solidity 0.8.26;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {HODLProxyAdmin} from "./HODLProxyAdmin.sol";


interface IHODLProxy is IERC1967 {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

contract HODLProxy is ERC1967Proxy {
   
    address private immutable _admin;

    error ProxyDeniedAdminAccess();

    constructor(
        address _logic,
        address initialOwner,
        address initialOwner2,
        address initialOwner3,
        bytes memory _data
    ) payable ERC1967Proxy(_logic, _data) {
        _admin = address(new HODLProxyAdmin(initialOwner, initialOwner2, initialOwner3));
        ERC1967Utils.changeAdmin(_proxyAdmin());
    }

    function _proxyAdmin() internal view virtual returns (address) {
        return _admin;
    }

    function _fallback() internal virtual override {
        if (msg.sender == _proxyAdmin()) {
            if (msg.sig != IHODLProxy.upgradeToAndCall.selector) {
                revert ProxyDeniedAdminAccess();
            } else {
                _dispatchUpgradeToAndCall();
            }
        } else {
            super._fallback();
        }
    }

    function _dispatchUpgradeToAndCall() private {
        (address newImplementation, bytes memory data) = abi.decode(msg.data[4:], (address, bytes));
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }
}