// SPDX-License-Identifier: MIT

//   __    __    ______    _____      __
//  |  |  |  |  /  __  \  |      \   |  |
//  |  |__|  | |  |  |  | |   _   \  |  |
//  |   __   | |  |  |  | |  |_)   | |  |
//  |  |  |  | |  `--'  | |       /  |  |____
//  |__|  |__|  \______/  |_____ /   |_______|
//                  HODL TOKEN

//  HODL Token Ownership Management Contract:
//  This contract provides ownership and administration controls for the HODL token contract.
//  It allows for multiple administrators with distinct roles, permissions for secure actions,
//  and custom error handling. This design enhances security and flexibility in managing the
//  token's critical functions.

pragma solidity 0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

abstract contract HODLOwnable is ContextUpgradeable {
    address private _owner;
    address private _owner2;
    address private _owner3;

    address private callPermittedBy;
    address private callPermittedTo;
    uint private permissionSetAt;

    error OwnableUnauthorizedAccount(address account);

    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner, string who);

    constructor(address initialOwner, address initialOwner2, address initialOwner3) {
        if (initialOwner == address(0) || initialOwner2 == address(0) || initialOwner3 == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
        _transferOwnership2(initialOwner2);
        _transferOwnership3(initialOwner3);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    modifier callPermitted() {
         _checkPermission();
        _;
        _cancelPermission();
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function owner2() public view virtual returns (address) {
        return _owner2;
    }

    function owner3() public view virtual returns (address) {
        return _owner3;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender() && owner2() != _msgSender() && owner3() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function _checkPermission() internal view {
        if (_msgSender() == callPermittedBy || permissionSetAt > block.timestamp + 60 || _msgSender() != callPermittedTo) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function _cancelPermission() internal {
        callPermittedBy = address(0);
        callPermittedTo = address(0);
    }

    function permitCall(address permitTo) external onlyOwner {
        require(_msgSender() != permitTo, "Cannot permit yourself!");
        permissionSetAt = block.timestamp;
        callPermittedBy = msg.sender;
        callPermittedTo = permitTo;
    }

    function renounceOwnership() public virtual onlyOwner callPermitted {
        _transferOwnership(address(0));
    }

    function renounceOwnership2() public virtual onlyOwner callPermitted {
        _transferOwnership2(address(0));
    }

    function renounceOwnership3() public virtual onlyOwner callPermitted {
        _transferOwnership3(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner callPermitted {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function transferOwnership2(address newOwner) public virtual onlyOwner callPermitted {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership2(newOwner);
    }

    function transferOwnership3(address newOwner) public virtual onlyOwner callPermitted {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership3(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner, "owner");
    }

    function _transferOwnership2(address newOwner) internal virtual {
        address oldOwner = _owner2;
        _owner2 = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner, "_owner2");
    }

    function _transferOwnership3(address newOwner) internal virtual {
        address oldOwner = _owner3;
        _owner3 = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner, "_owner3");
    }
}