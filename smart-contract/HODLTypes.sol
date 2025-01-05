// SPDX-License-Identifier: MIT

//   __    __    ______    _____      __
//  |  |  |  |  /  __  \  |      \   |  |
//  |  |__|  | |  |  |  | |   _   \  |  |
//  |   __   | |  |  |  | |  |_)   | |  |
//  |  |  |  | |  `--'  | |       /  |  |____
//  |__|  |__|  \______/  |_____ /   |_______|
//                  HODL TOKEN

//  HODLTypes Contract Summary:
//  This abstract contract provides foundational structures and custom errors for managing
//  HODL Token's reward stacking and daily sell limit. It includes data structures to 
//  track user activity and reward stacking status, as well as general error handling.

pragma solidity 0.8.26;

abstract contract HODLTypes {

    // Tracks user's activity for daily sell limit
    struct WalletAllowance {
        uint256 lastTransactionTimestamp;      // Timestamp of the last transaction
        uint256 dailySellVolume;               // Total tokens sold in the last 24 hours
    }

   // Tracks user’s reward stacking details
    struct RewardStacking {
        bool stackingIsActive;                 // Indicates if reward stacking is active
        uint64 claimCycle;                     // Reward claim cycle duration (in seconds)
        uint64 stackingStartTimestamp;         // Timestamp when reward stacking started
        uint96 rewardLimit;                    // Maximum BNB reward available when stacking
        uint96 stackedAmount;                  // Total amount of stacked tokens
        uint96 rewardPoolCapAtStart;           // Reward pool cap at the start of stacking
    }

    // Errors
    error ValueOutOfRange();
    error BNBTransferFailed();
    error StackingNotActive();
    error ClaimPeriodNotReached();
    error NoHODLInWallet();
    error ExceededDailySellLimit();
    error CooldownInEffect();
    error StackingNotEnabledOrAlreadyActive();
    error InsufficientBalanceForStacking();
}