// SPDX-License-Identifier: MIT

//   __    __    ______    _____      __
//  |  |  |  |  /  __  \  |      \   |  |
//  |  |__|  | |  |  |  | |   _   \  |  |
//  |   __   | |  |  |  | |  |_)   | |  |
//  |  |  |  | |  `--'  | |       /  |  |____
//  |__|  |__|  \______/  |_____ /   |_______|
//                  HODL TOKEN

//  HODL Token Proxy Admin Contract:
//  Provides administrative control over upgradeable proxies, enabling secure 
//  upgrades and initialization of new implementations. This contract is designed 
//  to facilitate safe upgrades and ensure authorized access through multi-owner permissions.

pragma solidity 0.8.26;

import {IHODLProxy} from "./HODLProxy.sol";
import {HODLOwnable} from "./HODLOwnable.sol";

contract HODLProxyAdmin is HODLOwnable {
 
    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    constructor(address initialOwner, address initialOwner2, address initialOwner3) HODLOwnable(initialOwner, initialOwner2, initialOwner3) {}

    function upgradeAndCall(
        IHODLProxy proxy,
        address implementation,
        bytes memory data
    ) public payable virtual onlyOwner callPermitted {
        proxy.upgradeToAndCall{value: msg.value}(implementation, data);
    }
}