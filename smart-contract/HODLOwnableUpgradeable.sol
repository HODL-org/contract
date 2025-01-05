// SPDX-License-Identifier: MIT

//   __    __    ______    _____      __
//  |  |  |  |  /  __  \  |      \   |  |
//  |  |__|  | |  |  |  | |   _   \  |  |
//  |   __   | |  |  |  | |  |_)   | |  |
//  |  |  |  | |  `--'  | |       /  |  |____
//  |__|  |__|  \______/  |_____ /   |_______|
//                  HODL TOKEN

//  HODL Token Upgradeable Ownership Contract:
//  This contract extends ownership functionality with multiple owners and a permission system,
//  designed for use in upgradable contracts. It uses a structured storage pattern to retain state
//  across upgrades and supports role-based permissions for secure contract management.

pragma solidity 0.8.26;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract HODLOwnableUpgradeable is Initializable, ContextUpgradeable {

    struct OwnableStorage {
        address _owner;
        address _owner2;
        address _owner3;
        address _permittedBy;
        address _permittedTo;
        uint _permittedAt;
    }

    bytes32 private constant OwnableStorageLocation = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;

    function _getOwnableStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            $.slot := OwnableStorageLocation
        }
    }

    error OwnableUnauthorizedAccount(address account);

    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function __Ownable_init(address initialOwner, address initialOwner2, address initialOwner3) internal onlyInitializing {
        __Ownable_init_unchained(initialOwner, initialOwner2, initialOwner3);
    }

    function __Ownable_init_unchained(address initialOwner, address initialOwner2, address initialOwner3) internal onlyInitializing {
        if (initialOwner == address(0) || initialOwner2 == address(0) || initialOwner3 == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
        _transferOwner2(initialOwner2);
        _transferOwner3(initialOwner3);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    modifier onlyPermitted() {
         _checkPermission();
        _;
        _cancelPermission();
    }

    function owner() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner;
    }

    function owner2() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner2;
    }

    function owner3() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner3;
    }

    function permittedBy() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._permittedBy;
    }

    function permittedTo() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._permittedTo;
    }

    function permittedAt() public view virtual returns (uint) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._permittedAt;
    }

    function _isOwner(address wallet) internal view virtual returns (bool) {
        return wallet == owner() || wallet == owner2() || wallet == owner3();
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender() && owner2() != _msgSender() && owner3() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function _checkPermission() internal view {
        if (_msgSender() == permittedBy() || block.timestamp > permittedAt() + 120 || _msgSender() != permittedTo()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function _cancelPermission() internal {
        OwnableStorage storage $ = _getOwnableStorage();
        $._permittedBy = address(0);
        $._permittedTo = address(0);
    }

    function givePermission(address to) external onlyOwner {
        require(_msgSender() != to, "Cannot permit yourself!");
        OwnableStorage storage $ = _getOwnableStorage();
        $._permittedAt = block.timestamp;
        $._permittedBy = _msgSender();
        $._permittedTo = to;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner onlyPermitted {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function transferOwner2(address newOwner) public virtual onlyOwner onlyPermitted {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwner2(newOwner);
    }

    function transferOwner3(address newOwner) public virtual onlyOwner onlyPermitted {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwner3(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        OwnableStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner;
        $._owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function _transferOwner2(address newOwner) internal virtual {
        OwnableStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner2;
        $._owner2 = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function _transferOwner3(address newOwner) internal virtual {
        OwnableStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner3;
        $._owner3 = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}