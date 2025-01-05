// SPDX-License-Identifier: MIT

//   __    __    ______    _____      __
//  |  |  |  |  /  __  \  |      \   |  |
//  |  |__|  | |  |  |  | |   _   \  |  |
//  |   __   | |  |  |  | |  |_)   | |  |
//  |  |  |  | |  `--'  | |       /  |  |____
//  |__|  |__|  \______/  |_____ /   |_______|
//                  HODL TOKEN
//
//  Website:   https://hodltoken.net
//  Telegram:  https://t.me/hodlinvestorgroup
//  X:         https://x.com/HODL_Official
//  Reddit:    https://reddit.com/r/HodlToken
//  Linktree:  https://linktr.ee/hodltoken

//  HODL Token Implementation Contract v1.02:
//  This contract delivers core functionalities for HODL token, such as reward distribution, transaction tax management,
//  token swaps, reward stacking, and reinvestment options. Built with a modular architecture and robust error handling,
//  it prioritizes security, efficiency, and maintainability to create a reliable experience for both users and developers.

pragma solidity 0.8.26;

import {HODLOwnableUpgradeable} from "./HODLOwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "https://github.com/pancakeswap/pancake-smart-contracts/projects/exchange-protocol/contracts/interfaces/IPancakeRouter02.sol";
import "./HODLTypes.sol";

contract HODL is
    ERC20Upgradeable,
    HODLOwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    HODLTypes
{
    // Constants for reward calculations and token management
    address public constant BURN_ADDRESS =
        0x000000000000000000000000000000000000dEaD;                     // Burn address for circulating supply calculation
    address public constant STACKING_ADDRESS =
        0x02A4FeE688cbD005690738874958Be07E67aE64B;                     // Designated address for tokens used in reward stacking
    address private constant REINVEST_ADDRESS =
        0xbafD57650Bd8c994A4ABcC14006609c9b83981f4;                     // Address for buying and transferring reinvestment tokens
    address public constant PANCAKE_PAIR =
        0x000000000000000000000000000000000000dEaD;                     // PancakeSwap liquidity pair address
    address public constant TRIGGER_WALLET =
        0xEbb38E4750d761e51D6DC51474C5C61a06E48F46;                     // Wallet permitted to trigger manual reward swaps
    address public constant BUSD_ADDRESS =
        0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;                     // BUSD address for token value calculation
    IPancakeRouter02 public constant PANCAKE_ROUTER =
        IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);   // PancakeSwap router for liquidity functions

    // Address status mappings
    mapping(address => bool) public isTaxFree;                      // Addresses exempt from buy/sell/transfer taxes
    mapping(address => bool) private isMMAddress;                   // Market maker addresses for simpler tax-free trades
    mapping(address => bool) public isPairAddress;                  // Approved liquidity pair addresses for tax logic
    mapping(address => bool) public isExcludedFromRewardPoolShare;  // Project tokens excluded to preserve investor reward claim %

    // User reward and transaction data
    mapping(address => uint256) public nextClaimDate;               // Next eligible reward claim timestamp
    mapping(address => uint256) public userBNBClaimed;              // Total BNB claimed as rewards
    mapping(address => uint256) public userReinvested;              // Total tokens claimed as reinvested rewards
    mapping(address => uint256) private userLastBuy;                // Timestamp of last buy transaction
    mapping(address => RewardStacking) public rewardStacking;       // User-specific reward stacking details
    mapping(address => WalletAllowance) public userWalletAllowance; // Wallet limits for max daily sell

    // Tokenomics settings and parameters
    uint256 public buyTax;                      // Buy transaction tax percentage
    uint256 public sellTax;                     // Sell transaction tax percentage
    uint256 public buySellCooldown;             // Cooldown period (in seconds) between consecutive buys/sells
    uint256 public maxSellAmount;               // Max tokens a user can sell per 24 hours
    uint256 private rewardPoolShare;            // Reward Pool Share used in reward calculations

    // Reward pool settings
    uint256 public minTokensTriggerRewardSwap;  // Minimum tokens required in reward pool to allow swaps
    uint256 public swapForRewardThreshold;      // Minimum sell amount in USD to trigger a reward swap
    uint256 private previousTokenBalance;       // Last $HODL token balance for dynamic reward swap % adjustment
    uint256 private previousHODLPrice;          // Last $HODL price for dynamic reward swap % adjustment
    uint256 private numberOfDeclines;           // Consectuctive drops in $HODL token balance for dynamic reward swap % adjustment

    // Reward timing and limitations
    uint256 public rewardClaimPeriod;           // Minimum period between reward claims (in seconds)
    uint256 public reinvestBonusCycle;          // Claim period reduction for reinvesting 100% of rewards (in seconds)
    uint256 public updateClaimDateRate;         // Threshold for updating user's reward claim timestamp based on balance increase %
    uint256 public bnbRewardPoolCap;            // Max BNB in reward pool used in reward calculations

    // Reward stacking parameters
    uint256 public bnbStackingLimit;            // Max reward amount claimable when stacking (in BNB)
    uint256 public minTokensToStack;            // Minimum tokens required to participate in stacking

    // Aggregated reward and reinvestment data
    uint256 public totalBNBClaimed;             // Total BNB claimed by all users
    uint256 public totalHODLFromReinvests;      // Total tokens reinvested by all users

    // Contract controls
    bool public rewardSwapEnabled;              // Toggle for enabling/disabling reward pool swaps
    bool public stackingEnabled;                // Toggle for enabling/disabling reward stacking
    bool private _inRewardSwap;                 // Internal lock to prevent reentrancy during reward swaps

    // Events for configuration changes
    event ChangeValue(
        uint256 indexed oldValue,
        uint256 indexed newValue,
        string variable
    ); // Logs value changes in contract parameters
    event ChangeAddress(
        address indexed oldAddress,
        address indexed newAddress,
        string variable
    ); // Logs address changes in contract parameters
    event ChangeAddressState(
        address indexed _address,
        bool indexed enable,
        string variable
    ); // Logs address state changes in contract parameters

    // Prevents reentrancy for reward swaps
    modifier lockTheSwap() {
        _inRewardSwap = true;
        _;
        _inRewardSwap = false;
    }

    // Accepts BNB sent directly to the contract
    receive() external payable {}

    function upgrade() external onlyOwner reinitializer(2) {
        isPairAddress[PANCAKE_PAIR] = true; // Mark pair as valid for tax/trading logic
        super._approve(
            address(this),
            address(PANCAKE_ROUTER),
            type(uint256).max
        ); // Approve router for unlimited token handling
    }

    // Ends stacking and claims rewards, applying similar logic as 'redeemReward' using stacked amount
    function stopStackingAndClaim(uint8 perc) external nonReentrant {
        if (perc > 100) revert ValueOutOfRange();

        RewardStacking memory tmpStack = rewardStacking[msg.sender];

        require(tmpStack.stackingIsActive, "Stacking not active");
        uint256 reward = getStacked(msg.sender);

        executeRedeemRewards(perc, reward);

        super._update(STACKING_ADDRESS, msg.sender, tmpStack.stackedAmount);

        delete rewardStacking[msg.sender];
    }

    // Initiates reward stacking by transferring eligible tokens to the designated reward stacking address
    function startStacking() external {
        uint256 userBalance = super.balanceOf(msg.sender);
        require(userBalance > 1 ether, "Not enough tokens!");

        uint256 balance = userBalance - 1 ether; // Leaves 1 token behind to maintain holders count

        if (!stackingEnabled || rewardStacking[msg.sender].stackingIsActive)
            revert StackingNotEnabledOrAlreadyActive();
        if (nextClaimDate[msg.sender] > block.timestamp)
            revert ClaimPeriodNotReached();
        if (balance < minTokensToStack) revert InsufficientBalanceForStacking();

        rewardStacking[msg.sender] = RewardStacking(
            true,
            uint64(rewardClaimPeriod),
            uint64(block.timestamp),
            uint96(bnbStackingLimit),
            uint96(balance),
            uint96(bnbRewardPoolCap)
        );

        super._update(msg.sender, STACKING_ADDRESS, balance);
    }

    // Claims rewards in BNB and or tokens based on user's choice, accounting for reward pool cap
    function redeemRewards(uint8 perc) external nonReentrant {
        if (perc > 100) revert ValueOutOfRange();

        uint256 userBalance = super.balanceOf(msg.sender);

        if (nextClaimDate[msg.sender] > block.timestamp)
            revert ClaimPeriodNotReached();
        if (userBalance == 0) revert NoHODLInWallet();

        uint256 currentBNBPool = address(this).balance;
        uint256 reward = currentBNBPool > bnbRewardPoolCap
            ? (bnbRewardPoolCap * userBalance) / rewardPoolShare
            : (currentBNBPool * userBalance) / rewardPoolShare;

        executeRedeemRewards(perc, reward);
    }

    // Excludes or includes an address from taxes
    function updateIsTaxFree(
        address wallet,
        bool taxFree
    ) external onlyOwner onlyPermitted {
        isTaxFree[wallet] = taxFree;
        emit ChangeAddressState(wallet, taxFree, "isTaxFree");
    }

    // Excludes or includes an address from circulating supply
    function excludeFromRewardPoolShare(
        address wallet,
        bool isExcluded
    ) external onlyOwner onlyPermitted {
        if (isExcluded && !isExcludedFromRewardPoolShare[wallet]) {
            rewardPoolShare -= super.balanceOf(wallet);
        } else if (!isExcluded && isExcludedFromRewardPoolShare[wallet]) {
            rewardPoolShare += super.balanceOf(wallet);
        }
        isExcludedFromRewardPoolShare[wallet] = isExcluded;
        emit ChangeAddressState(
            wallet,
            isExcluded,
            "isExcludedFromRewardPoolShare"
        );
    }

    // Adjusts buy tax percentage
    function changeBuyTaxes(uint256 newTax) external onlyOwner onlyPermitted {
        if (newTax > 20) revert ValueOutOfRange();
        uint256 oldTax = buyTax;
        buyTax = newTax;
        emit ChangeValue(oldTax, newTax, "buyTax");
    }

    // Adjusts sell tax percentage
    function changeSellTaxes(uint256 newTax) external onlyOwner onlyPermitted {
        if (newTax > 20) revert ValueOutOfRange();
        uint256 oldTax = sellTax;
        sellTax = newTax;
        emit ChangeValue(oldTax, newTax, "sellTax");
    }

    // Updates max sell limit per user per 24 hours
    function changeMaxSellAmount(
        uint256 newValue
    ) external onlyOwner onlyPermitted {
        if (
            newValue < (super.totalSupply() * 25) / 10_000 ||
            newValue > (super.totalSupply() * 500) / 10_000
        ) revert ValueOutOfRange();
        uint256 oldValue = maxSellAmount;
        maxSellAmount = newValue;
        emit ChangeValue(oldValue, newValue, "maxSellAmount");
    }

    // Sets minimum tokens required in reward pool to allow reward swaps
    function changeMinTokensTriggerRewardSwap(
        uint256 newValue
    ) external onlyOwner onlyPermitted {
        uint256 oldValue = minTokensTriggerRewardSwap;
        minTokensTriggerRewardSwap = newValue;
        emit ChangeValue(oldValue, newValue, "minTokensTriggerRewardSwap");
    }

    // Sets threshold sell amount in USD to trigger a reward pool swap
    function changeSwapForRewardThreshold(
        uint256 newValue
    ) external onlyOwner onlyPermitted {
        uint256 oldValue = swapForRewardThreshold;
        swapForRewardThreshold = newValue;
        emit ChangeValue(oldValue, newValue, "swapForRewardThreshold");
    }

    // Sets BNB reward pool cap used in reward calculations
    function changeBnbRewardPoolCap(
        uint256 newValue
    ) external onlyOwner onlyPermitted {
        uint256 oldValue = bnbRewardPoolCap;
        bnbRewardPoolCap = newValue;
        emit ChangeValue(oldValue, newValue, "bnbRewardPoolCap");
    }

    // Adjusts standard reward claim period (in seconds)
    function changeRewardClaimPeriod(
        uint256 newValue
    ) external onlyOwner onlyPermitted {
        uint256 oldValue = rewardClaimPeriod;
        rewardClaimPeriod = newValue;
        emit ChangeValue(oldValue, newValue, "rewardClaimPeriod");
    }

    // Updates threshold for claim timestamp update based on user balance increase (%)
    function changeUpdateClaimDateRate(
        uint256 newValue
    ) external onlyOwner onlyPermitted {
        uint256 oldValue = updateClaimDateRate;
        updateClaimDateRate = newValue;
        emit ChangeValue(oldValue, newValue, "updateClaimDateRate");
    }

    // Sets claim period deduction for users who reinvest 100% of their rewards (in seconds)
    function changeReinvestBonusCycle(
        uint256 newValue
    ) external onlyOwner onlyPermitted {
        uint256 oldValue = reinvestBonusCycle;
        reinvestBonusCycle = newValue;
        emit ChangeValue(oldValue, newValue, "reinvestBonusCycle");
    }

    // Sets the cooldown period (in seconds) between consecutive buys/sells
    function changeBuySellCooldown(
        uint256 newValue
    ) external onlyOwner onlyPermitted {
        if (newValue > 5 minutes) revert ValueOutOfRange();
        uint256 oldValue = buySellCooldown;
        buySellCooldown = newValue;
        emit ChangeValue(oldValue, newValue, "buySellCooldown");
    }

    // Enables or disables a liquidity pool pairing address
    function updatePairAddress(
        address wallet,
        bool _enable
    ) external onlyOwner onlyPermitted {
        isPairAddress[wallet] = _enable;
        emit ChangeAddressState(wallet, _enable, "isPairAddress");
    }

    // Enables or disables a market maker address
    function updateMMAddress(
        address[] calldata wallets,
        bool _enable
    ) external onlyOwner onlyPermitted {
        for (uint i=0; i< wallets.length; i++) {
            isMMAddress[wallets[i]] = _enable;
            emit ChangeAddressState(wallets[i], _enable, "isMMAddress");
        }
    }

    // Manually trigger a reward swap using the designated trigger wallet
    function triggerSwapForReward() external lockTheSwap onlyPermitted {
        require(
            msg.sender == address(TRIGGER_WALLET) && rewardSwapEnabled,
            "Unauthorized or swap disabled"
        );
        uint256 contractTokenBalance = super.balanceOf(address(this));
        uint256 currentPoolBalance = address(this).balance;
        uint256 tokensToSell = getTokensToSell(
            currentPoolBalance,
            contractTokenBalance
        );
        swapTokensForEth(tokensToSell);
    }

    // Calculates the user's eligible BNB reward based on their balance and the reward pool cap
    function getCurrentBNBReward(
        address wallet
    ) external view returns (uint256) {
        uint256 currentBalance = super.balanceOf(address(wallet));
        uint256 currentBNBPool = address(this).balance;
        uint256 bnbPool = currentBNBPool > bnbRewardPoolCap
            ? bnbRewardPoolCap
            : currentBNBPool;
        return (bnbPool * currentBalance) / rewardPoolShare;
    }

    // Returns updated reward pool share figure
    function getRewardPoolShare() public view returns (uint256) {
        return rewardPoolShare;
    }

    // Converts token amount to USD value for determining if a reward swap threshold is met
    function getTokensValue(uint256 tokenAmount) public view returns (uint256) {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = PANCAKE_ROUTER.WETH();
        path[2] = BUSD_ADDRESS;
        return PANCAKE_ROUTER.getAmountsOut(tokenAmount, path)[2];
    }

    // Calculates reward claim for users participating in reward stacking
    function getStacked(address wallet) public view returns (uint256) {
        RewardStacking memory tmpStack = rewardStacking[wallet];
        if (!tmpStack.stackingIsActive) {
            return 0;
        }

        uint256 stackedTotal = 1E6 +
            ((block.timestamp - tmpStack.stackingStartTimestamp) * 1E6) /
            tmpStack.claimCycle;
        uint256 stacked = stackedTotal / 1E6;
        uint256 rest = stackedTotal - (stacked * 1E6);

        uint256 initialBalance = address(this).balance;
        uint256 currentRewardPoolShare = rewardPoolShare;

        uint256 reward;
        if (initialBalance >= tmpStack.rewardPoolCapAtStart) {
            reward =
                (((uint256(tmpStack.rewardPoolCapAtStart) *
                    tmpStack.stackedAmount) / currentRewardPoolShare) *
                    stackedTotal) /
                1E6;
            if (
                reward >= initialBalance ||
                initialBalance - reward < tmpStack.rewardPoolCapAtStart
            ) {
                reward = _calculateStackedReward(
                    initialBalance,
                    tmpStack,
                    stacked,
                    rest,
                    currentRewardPoolShare
                );
            }
        } else {
            reward = _calculateStackedReward(
                initialBalance,
                tmpStack,
                stacked,
                rest,
                currentRewardPoolShare
            );
        }

        return
            reward > tmpStack.rewardLimit
                ? uint256(tmpStack.rewardLimit)
                : reward;
    }

    function _calculateStackedReward(
        uint256 initialBalance,
        RewardStacking memory tmpStack,
        uint256 stacked,
        uint256 rest,
        uint256 currentRewardPoolShare
    ) internal pure returns (uint256) {
        uint256 reward = initialBalance -
            calculateReward(
                initialBalance,
                currentRewardPoolShare / tmpStack.stackedAmount,
                stacked,
                15
            );
        reward +=
            ((((initialBalance - reward) * tmpStack.stackedAmount) /
                currentRewardPoolShare) * rest) /
            1E6;
        return reward;
    }

    // Handles transfers with tax and cooldown logic
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {

        // Contract paused until initial setup
        require(_isOwner(from) || _isOwner(to) || from == 0xC5C914fbdDeA7270051EDC1dd57c0Ac9621A52dc || to == 0xC5C914fbdDeA7270051EDC1dd57c0Ac9621A52dc, "Contract paused while initial setup!");
        
        uint256 tax = buyTax; // Default tax for buy transactions
        if (isMMAddress[from] || isMMAddress[to]) {
            super._update(from, to, value); // Checks if it's a market maker address for simplified tax-free transaction
        } else {
            bool takeFee = !(isTaxFree[from] || isTaxFree[to]); // Applies fee, unless address is tax exempt

            // Handle sell transactions
            if (isPairAddress[to] && from != address(this) && !_isOwner(from)) {
                if (block.timestamp <= userLastBuy[from] + buySellCooldown)
                    revert CooldownInEffect();
                ensureMaxSellAmount(from, value); // Enforce max sell limit

                // Checks reward swap trigger conditions
                if (
                    rewardSwapEnabled &&
                    !_inRewardSwap &&
                    getTokensValue(value) > swapForRewardThreshold
                ) {
                    swapForReward(from, to);
                }
                tax = sellTax;
            }
            // Handle buy transactions
            else if (
                isPairAddress[from] && to != address(this) && !_isOwner(from)
            ) {
                userLastBuy[to] = block.timestamp; // Track last buy timestamp for cooldown enforcement
            }

            // Apply tax if applicable and update balances
            if (takeFee) {
                uint256 fees = (value * tax) / 100;
                value -= fees;
                super._update(from, address(this), fees);
            }

            // Transfer remaining value to the recipient after tax deduction
            super._update(from, to, value);
            if (!isPairAddress[to]) updateClaimDateAfterTransfer(to, value); // Updates next claim timestamp based on balance changes
            updateRewardPoolShare(value, from, to); // Update reward pool share figure
        }
    }

    // Updates and stores circulating supply based on total supply minus burned tokens and excluded addresses
    function updateRewardPoolShare(
        uint256 value,
        address from,
        address to
    ) private {
        if (isExcludedFromRewardPoolShare[from]) rewardPoolShare += value;
        if (isExcludedFromRewardPoolShare[to]) rewardPoolShare -= value;
    }

    // Ensures daily sell limit is enforced for each user
    function ensureMaxSellAmount(address from, uint256 amount) private {
        WalletAllowance storage wallet = userWalletAllowance[from];

        // Reset daily sell allowance if 24 hours have passed since last transaction
        if (block.timestamp > wallet.lastTransactionTimestamp + 1 days) {
            wallet.lastTransactionTimestamp = 0;
            wallet.dailySellVolume = 0;
        }

        uint256 totalAmount = wallet.dailySellVolume + amount;
        if (totalAmount > maxSellAmount) revert ExceededDailySellLimit();

        // Update daily allowance tracking
        if (wallet.lastTransactionTimestamp == 0) {
            wallet.lastTransactionTimestamp = block.timestamp;
        }
        wallet.dailySellVolume = totalAmount;
    }

    function executeRedeemRewards(uint8 perc, uint256 reward) private {
        uint256 rewardReinvest = 0;
        uint256 rewardBNB = 0;
        uint256 nextClaim = block.timestamp + rewardClaimPeriod;

        unchecked {
            if (perc == 100) {
                rewardBNB = reward;
            } else if (perc == 0) {
                rewardReinvest = reward;
                nextClaim -= reinvestBonusCycle;
            } else {
                rewardBNB = (reward * perc) / 100;
                rewardReinvest = reward - rewardBNB;
            }
        }

        if (perc < 100) {
            address[] memory path = new address[](2);
            path[0] = PANCAKE_ROUTER.WETH();
            path[1] = address(this);

            uint256[] memory expectedtoken = PANCAKE_ROUTER.getAmountsOut(
                rewardReinvest,
                path
            );
            userReinvested[msg.sender] += expectedtoken[1];
            totalHODLFromReinvests += expectedtoken[1];

            PANCAKE_ROUTER.swapExactETHForTokens{value: rewardReinvest}(
                expectedtoken[1],
                path,
                REINVEST_ADDRESS,
                block.timestamp + 360
            );
            super._update(REINVEST_ADDRESS, msg.sender, expectedtoken[1]);
        }

        if (rewardBNB > 0) {
            (bool success, ) = address(msg.sender).call{value: rewardBNB}("");
            if (!success) revert BNBTransferFailed();
            userBNBClaimed[msg.sender] += rewardBNB;
            totalBNBClaimed += rewardBNB;
        }
        nextClaimDate[msg.sender] = nextClaim;
    }

    // Updates the next eligible claim timestamp after a token transfer
    function updateClaimDateAfterTransfer(address to, uint256 value) private {
        uint256 currentBalance = super.balanceOf(to);
        uint256 nextClaim = nextClaimDate[to];
        if ((_isOwner(to) && nextClaim == 0) || currentBalance == 0) {
            nextClaimDate[to] = block.timestamp + rewardClaimPeriod;
        } else {
            nextClaim += calculateUpdateClaim(currentBalance, value);
            nextClaimDate[to] = nextClaim > block.timestamp + rewardClaimPeriod
                ? block.timestamp + rewardClaimPeriod
                : nextClaim;
        }
    }

    // Triggers a swap of tokens in the reward pool for BNB to fund rewards, meeting specific conditions
    function swapForReward(address from, address to) private lockTheSwap {
        uint256 contractTokenBalance = super.balanceOf(address(this));
        uint256 currentPoolBalance = address(this).balance;

        // Trigger reward swap if pool balance meets threshold and is below cap
        if (
            contractTokenBalance >= minTokensTriggerRewardSwap &&
            currentPoolBalance <= bnbRewardPoolCap &&
            from != PANCAKE_PAIR &&
            !(from == address(this) && to == address(PANCAKE_PAIR))
        ) {
            uint256 tokensToSell = getTokensToSell(
                currentPoolBalance,
                contractTokenBalance
            );
            if (tokensToSell > 0) swapTokensForEth(tokensToSell);
        }
    }

    // Calculates reward swap % based on reward pool balance, $HODL price changes, and token balance decay
    function getTokensToSell(
        uint256 currentPoolBalance,
        uint256 contractTokenBalance
    ) private returns (uint256 tokensToSell) {
        // Reward Pool Percentage: Decreases the swap percentage as the reward pool approaches its cap (in basis points, max 2.50%)
        uint256 rewardPoolSwapPercentage = currentPoolBalance < bnbRewardPoolCap
            ? ((10000 - ((currentPoolBalance * 10000) / bnbRewardPoolCap)) *
                250) / 10000
            : 0;
        uint256 currentHODLPrice = getTokensValue(1 ether); // Fetch the current $HODL price in BNB (1 ether tokens = 1 unit)

        // Calculate the percentage change in $HODL price since the last check: Positive values indicate price growth; negative values indicate a drop
        int256 priceChange = ((int256(currentHODLPrice) * 10000) /
            int256(previousHODLPrice)) - 10000; // Example: 2500 = 25%
        previousHODLPrice = currentHODLPrice;

        // Price-Based Swap Percentage: Base is 6.00%, adjusted by 1/5 of the price change (clamped between 0% and 10%)
        int256 priceSwapPercentage = 600 + (priceChange / 5);

        // Clamp the price-based percentage within a valid range (0% to 10%)
        if (priceSwapPercentage < 0) {
            priceSwapPercentage = 0;
        } else if (priceSwapPercentage > 1000) {
            priceSwapPercentage = 1000;
        }

        uint256 tokenSwapPercentage = 250; // Base Token Swap Percentage: Default is 2.50% of the reward pool tokens

        // Token Balance Decay: Adjust swap percentage based on consecutive declines in contract token balance
        if (contractTokenBalance < previousTokenBalance) {
            if (numberOfDeclines < 3) numberOfDeclines += 1;
            tokenSwapPercentage = 225 - numberOfDeclines * 75; // Reduce by 0.75% per decline, down to 0% after 3 declines
        } else {
            numberOfDeclines = 0; // Reset decline count if token balance stabilizes or increases
        }

        // Combine all calculated percentages to determine the total swap percentage
        uint256 swapPercentage = rewardPoolSwapPercentage +
            uint256(priceSwapPercentage) +
            tokenSwapPercentage;

        // Calculate the total tokens to sell based on the combined percentage (in basis points) and the contract token balance
        return (contractTokenBalance * swapPercentage) / 10000;
    }

    // Swaps tokens for BNB using PancakeSwap to fund the reward pool
    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = PANCAKE_ROUTER.WETH();
        PANCAKE_ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    // Calculates and returns the updated claim timestamp based on user's balance increase
    function calculateUpdateClaim(
        uint256 currentRecipientBalance, // The current balance of the recipient
        uint256 value // The value of the tokens being transferred
    ) private view returns (uint256) {
        uint256 rate = (value * 100) / currentRecipientBalance; // Calculate percentage increase in holdings

        // Update next eligible reward claim timestamp if rate exceeds threshold
        if (rate >= updateClaimDateRate) {
            uint256 newCycleBlock = (rewardClaimPeriod * rate) / 100;
            newCycleBlock = newCycleBlock >= rewardClaimPeriod
                ? rewardClaimPeriod
                : newCycleBlock;
            return newCycleBlock;
        }
        return 0;
    }

    // Computes rewards with precision-based calculations to prevent overflow
    function calculateReward(
        uint256 coefficient,
        uint256 factor,
        uint256 exponent,
        uint256 precision
    ) private pure returns (uint256) {
        precision = exponent < precision ? exponent : precision;
        if (exponent > 100) {
            precision = 30;
        }
        if (exponent > 200) exponent = 200;

        uint256 reward = coefficient;
        uint256 calcExponent = (exponent * (exponent - 1)) / 2;
        uint256 calcFactorOne = 1;
        uint256 calcFactorTwo = 1;
        uint256 calcFactorThree = 1;
        uint256 i;

        for (i = 2; i <= precision; i += 2) {
            if (i > 20) {
                calcFactorOne = factor ** 10;
                calcFactorTwo = calcFactorOne;
                calcFactorThree = factor ** (i - 20);
            } else if (i > 10) {
                calcFactorOne = factor ** 10;
                calcFactorTwo = factor ** (i - 10);
                calcFactorThree = 1;
            } else {
                calcFactorOne = factor ** i;
                calcFactorTwo = 1;
                calcFactorThree = 1;
            }
            reward +=
                (coefficient * calcExponent) /
                calcFactorOne /
                calcFactorTwo /
                calcFactorThree;
            calcExponent = i == exponent
                ? 0
                : (calcExponent * (exponent - i) * (exponent - i - 1)) /
                    (i + 1) /
                    (i + 2);
        }

        calcExponent = exponent;

        for (i = 1; i <= precision; i += 2) {
            if (i > 20) {
                calcFactorOne = factor ** 10;
                calcFactorTwo = calcFactorOne;
                calcFactorThree = factor ** (i - 20);
            } else if (i > 10) {
                calcFactorOne = factor ** 10;
                calcFactorTwo = factor ** (i - 10);
                calcFactorThree = 1;
            } else {
                calcFactorOne = factor ** i;
                calcFactorTwo = 1;
                calcFactorThree = 1;
            }
            reward -=
                (coefficient * calcExponent) /
                calcFactorOne /
                calcFactorTwo /
                calcFactorThree;
            calcExponent = i == exponent
                ? 0
                : (calcExponent * (exponent - i) * (exponent - i - 1)) /
                    (i + 1) /
                    (i + 2);
        }
        return reward;
    }
}
