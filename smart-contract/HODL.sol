// SPDX-License-Identifier: MIT

//  __    __    ______    _____      __
// |  |  |  |  /  __  \  |      \   |  |
// |  |__|  | |  |  |  | |   _   \  |  |
// |   __   | |  |  |  | |  |_)   | |  |
// |  |  |  | |  `--'  | |       /  |  |____
// |__|  |__|  \______/  |_____ /   |_______|
//                 HODL TOKEN
//
// Website:    https://hodltoken.net
// Telegram:   https://t.me/hodlinvestorgroup
// X:          https://x.com/HODL_Official
// Reddit:     https://reddit.com/r/HodlToken
// Linktree:   https://linktr.ee/hodltoken

// HODL Token Implementation Contract v1.12:
// This contract delivers core functionalities for HODL token, such as reward distribution, transaction tax management,
// token swaps, reward stacking, and reinvestment options. Built with a modular architecture and robust error handling,
// it prioritizes security, efficiency, and maintainability to create a reliable experience for both users and developers.

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
        0x000000000000000000000000000000000000dEaD; // Burn address for circulating supply calculation
    address private constant MMUPDATER_ADDRESS =
        0x438245a4C3508d3F3DEabB5093569125D0D19B44; // Address for updating market maker addresses
    address private constant REINVEST_ADDRESS =
        0xbafD57650Bd8c994A4ABcC14006609c9b83981f4; // Address for buying and transferring reinvestment tokens
    address public constant PANCAKE_PAIR =
        0xC5c4F99423DfD4D2b73D863aEe50750468e45C19; // PancakeSwap liquidity pair address
    address public constant TRIGGER_WALLET =
        0xC32F84D0a435cd8ebAd6b02c82064028F848a8bd; // Wallet permitted to trigger manual reward swaps
    address public constant USDT_ADDRESS =
        0x55d398326f99059fF775485246999027B3197955; // USDT address for token value calculation
    IPancakeRouter02 public constant PANCAKE_ROUTER =
        IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // PancakeSwap router for liquidity functions

    // Address status mappings
    mapping(address => bool) public isTaxFree; // Addresses exempt from buy/sell/transfer taxes
    mapping(address => bool) private isMMAddress; // Market maker addresses for simpler tax-free trades
    mapping(address => bool) public isPairAddress; // Approved liquidity pair addresses for tax logic
    mapping(address => bool) public isExcludedFromRewardPoolShare; // Project tokens excluded to preserve investor reward claim %

    // User reward and transaction data
    mapping(address => uint256) public nextClaimDate; // Next eligible reward claim timestamp
    mapping(address => uint256) public userBNBClaimed; // Total BNB claimed as rewards by all users
    mapping(address => uint256) public userReinvested; // Total tokens claimed as reinvested rewards
    mapping(address => uint256) private userLastBuy; // Timestamp of last buy transaction
    mapping(address => RewardStacking) private rewardStacking; // [UNUSED] User-specific reward stacking details
    mapping(address => WalletAllowance) public userWalletAllowance; // Wallet limits for max daily sell

    // Tokenomics settings and parameters
    uint256 public reserve_int_3; // Reserve
    uint256 public reserve_int_4; // Reserve
    uint256 public buySellCooldown; // Cooldown period (in seconds) between consecutive buys/sells
    uint256 public maxSellAmount; // Max tokens a user can sell per 24 hours
    uint256 private rewardPoolShare; // Reward Pool Share used in reward calculations

    // Reward pool settings
    uint256 public minTokensTriggerRewardSwap; // Minimum tokens required in reward pool to allow swaps
    uint256 public swapForRewardThreshold; // Minimum sell amount in USD to trigger a reward swap
    uint256 private previousTokenBalance; // Last $HODL token balance for dynamic reward swap % adjustment
    uint256 private previousHODLPrice; // Last $HODL price for dynamic reward swap % adjustment
    uint256 private numberOfDeclines; // Consectuctive drops in $HODL token balance for dynamic reward swap % adjustment

    // Reward timing and limitations
    uint256 public rewardClaimPeriod; // Minimum period between reward claims (in seconds)
    uint256 public reinvestBonusCycle; // Claim period reduction for reinvesting 100% of rewards (in seconds)
    uint256 public updateClaimDateRate; // Threshold for updating user's reward claim timestamp based on balance increase %
    uint256 public bnbRewardPoolCap; // Max BNB in reward pool used in reward calculations

    // Rsserves
    uint256 private reserve_int_1; // Reserve
    uint256 private reserve_int_2; // Reserve

    // Aggregated reward and reinvestment data
    uint256 public totalBNBClaimed; // Total BNB claimed by all users
    uint256 public totalHODLFromReinvests; // Total tokens reinvested by all users

    // Contract controls
    bool public rewardSwapEnabled; // Toggle for enabling/disabling reward pool swaps
    bool private reserve_bool; // Reserve
    bool private _inRewardSwap; // Internal lock to prevent reentrancy during reward swaps

    address private constant RESERVE_ADDRESS =
        0x0000000000000000000000000000000000000000;

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
    event Log(string message); // Log messages

    // Prevents reentrancy for reward swaps
    modifier lockTheSwap() {
        _inRewardSwap = true;
        _;
        _inRewardSwap = false;
    }

    // Accepts BNB sent directly to the contract
    receive() external payable {}

    function upgrade() external onlyOwner reinitializer(5) {
        reinvestBonusCycle = 86400;
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

            PANCAKE_ROUTER.swapExactETHForTokens{value: rewardReinvest}(
                0,
                path,
                REINVEST_ADDRESS,
                block.timestamp + 360
            );
            uint256 transferredAmount = super.balanceOf(REINVEST_ADDRESS);
            userReinvested[msg.sender] += transferredAmount;
            totalHODLFromReinvests += transferredAmount;

            super._update(REINVEST_ADDRESS, msg.sender, transferredAmount);
        }

        if (rewardBNB > 0) {
            (bool success, ) = address(msg.sender).call{value: rewardBNB}("");
            if (!success) revert BNBTransferFailed();
            userBNBClaimed[msg.sender] += rewardBNB;
            totalBNBClaimed += rewardBNB;
        }
        nextClaimDate[msg.sender] = nextClaim;
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
        bool enable
    ) external onlyOwner onlyPermitted {
        isPairAddress[wallet] = enable;
        emit ChangeAddressState(wallet, enable, "isPairAddress");
    }

    // Enables or disables a market maker address
    function updateMMAddress(address[] calldata wallets, bool enable) external {
        require(msg.sender == address(MMUPDATER_ADDRESS), "Unauthorized");
        for (uint i = 0; i < wallets.length; i++) {
            isMMAddress[wallets[i]] = enable;
            emit ChangeAddressState(wallets[i], enable, "isMMAddress");
        }
    }

    // Manually trigger a reward swap using the designated trigger wallet
    function triggerSwapForReward() external lockTheSwap {
        require(msg.sender == address(TRIGGER_WALLET), "Unauthorized");
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
        path[2] = USDT_ADDRESS;
        return PANCAKE_ROUTER.getAmountsOut(tokenAmount, path)[2];
    }

    // Handles transfers with tax and cooldown logic
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        if (isMMAddress[from] || isMMAddress[to]) {
            super._update(from, to, value); // Checks if it's a market maker address for simplified tax-free transaction
            updateRewardPoolShare(value, from, to); // Update reward pool share figure
        } else {
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
            }
            // Handle buy transactions
            else if (
                isPairAddress[from] && to != address(this) && !_isOwner(from)
            ) {
                userLastBuy[to] = block.timestamp; // Track last buy timestamp for cooldown enforcement
            }

            // Apply tax if applicable and update balances
            if (!(isTaxFree[from] || isTaxFree[to])) {
                uint256 fees = (value * 5) / 100; // 5% Tax
                value -= fees;
                super._update(from, address(this), fees);
                updateRewardPoolShare(fees, from, address(this)); // Update reward pool share figure
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

    // Updates the next eligible claim timestamp after a token transfer
    function updateClaimDateAfterTransfer(address to, uint256 value) private {
        uint256 currentBalance = super.balanceOf(to);
        uint256 nextClaim = nextClaimDate[to];
        if (nextClaim == 0 || currentBalance == 0) {
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
        return (contractTokenBalance * swapPercentage) / 100000;
    }

    // Swaps tokens for BNB using PancakeSwap to fund the reward pool
    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = PANCAKE_ROUTER.WETH();
        try
            PANCAKE_ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
                tokenAmount,
                0,
                path,
                address(this),
                block.timestamp
            )
        {
            emit Log("Swapped tokens for reward!");
        } catch {
            emit Log("Rewardswap failed!");
        }
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

    // Transfer lost tokens
    function transferLostTokens(address from) external onlyOwner {
        uint256 transferredAmount = super.balanceOf(from);
        super._update(from, msg.sender, transferredAmount);
    }
}
