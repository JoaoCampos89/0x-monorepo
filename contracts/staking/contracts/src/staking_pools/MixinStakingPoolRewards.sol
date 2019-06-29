/*

  Copyright 2018 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.5.5;

import "../libs/LibSafeMath.sol";
import "../libs/LibRewardMath.sol";
import "../immutable/MixinStorage.sol";
import "../immutable/MixinConstants.sol";
import "../stake/MixinStakeBalances.sol";
import "./MixinStakingPoolRewardVault.sol";
import "./MixinStakingPool.sol";


contract MixinStakingPoolRewards is
    IStakingEvents,
    MixinDeploymentConstants,
    MixinConstants,
    MixinStorage,
    MixinOwnable,
    MixinScheduler,
    MixinStakingPoolRewardVault,
    MixinStakingPool,
    MixinTimelockedStake,
    MixinStakeBalances
{

    /// @dev This mixin contains logic for staking pool rewards.
    /// Rewards for a pool are generated by their market makers trading on the 0x protocol (MixinStakingPool).
    /// The operator of a pool receives a fixed percentage of all rewards; generally, the operator is the
    /// sole market maker of a pool. The remaining rewards are divided among the members of a pool; each member
    /// gets an amount proportional to how much stake they have delegated to the pool.
    ///
    /// Note that members can freely join or leave a staking pool at any time, by delegating/undelegating their stake.
    /// Moreover, there is no limit to how many members a pool can have. To limit the state-updates needed to track member balances,
    /// we store only a single balance shared by all members. This state is updated every time a reward is paid to the pool - which
    /// is currently at the end of each epoch. Additionally, each member has an associated "Shadow Balance" which is updated only
    /// when a member delegates/undelegates stake to the pool, along with a "Total Shadow Balance" that represents the cumulative
    /// Shadow Balances of all members in a pool.
    /// 
    /// -- Member Balances --
    /// Terminology:
    ///     Real Balance - The reward balance in ETH of a member.
    ///     Total Real Balance - The sum total of reward balances in ETH across all members of a pool.
    ///     Shadow Balance - The realized reward balance of a member.
    ///     Total Shadow Balance - The sum total of realized reward balances across all members of a pool.
    /// How it works:
    /// 1. When a member delegates, their ownership of the pool increases; however, this new ownership applies
    ///    only to future rewards and must not change the rewards currently owned by other members. Thus, when a
    ///    member delegates stake, we *increase* their Shadow Balance and the Total Shadow Balance of the pool.
    ///
    /// 2. When a member withdraws a portion of their reward, their realized balance increases but their ownership
    ///    within the pool remains unchanged. Thus, we simultaneously *decrease* their Real Balance and 
    ///    *increase* their Shadow Balance by the amount withdrawn. The cumulative balance decrease and increase, respectively.
    ///
    /// 3. When a member undelegates, the portion of their reward that corresponds to that stake is also withdrawn. Thus,
    ///    their realized balance *increases* while their ownership of the pool *decreases*. To reflect this, we 
    ///    decrease their Shadow Balance, the Total Shadow Balance, their Real Balance, and the Total Real Balance.

    using LibSafeMath for uint256;

    /// @dev Withdraws an amount in ETH of the reward for the pool operator.
    /// @param poolId Unique id of pool.
    /// @param amount The amount to withdraw.
    function withdrawRewardForStakingPoolOperator(bytes32 poolId, uint256 amount)
        external
        onlyStakingPoolOperator(poolId)
    {
        _withdrawFromOperatorInStakingPoolRewardVault(poolId, amount);
        poolById[poolId].operatorAddress.transfer(amount);
    }

    /// @dev Withdraws the total balance in ETH of the reward for the pool operator.
    /// @param poolId Unique id of pool.
    /// @return The amount withdrawn.
    function withdrawTotalRewardForStakingPoolOperator(bytes32 poolId)
        external
        onlyStakingPoolOperator(poolId)
        returns (uint256)
    {
        uint256 amount = getBalanceOfOperatorInStakingPoolRewardVault(poolId);
        _withdrawFromOperatorInStakingPoolRewardVault(poolId, amount);
        poolById[poolId].operatorAddress.transfer(amount);

        return amount;
    }

    /// @dev Withdraws an amount in ETH of the reward for a pool member.
    /// @param poolId Unique id of pool.
    /// @param amount The amount to withdraw.
    function withdrawRewardForStakingPoolMember(bytes32 poolId, uint256 amount)
        external
    {
        // sanity checks
        address payable member = msg.sender;
        uint256 memberBalance = computeRewardBalanceOfStakingPoolMember(poolId, member);
        require(
            amount <= memberBalance,
            "INVALID_AMOUNT"
        );

        // update shadow rewards
        shadowRewardsInPoolByOwner[member][poolId] = shadowRewardsInPoolByOwner[member][poolId]._add(amount);
        shadowRewardsByPoolId[poolId] = shadowRewardsByPoolId[poolId]._add(amount);

        // perform withdrawal
        _withdrawFromMemberInStakingPoolRewardVault(poolId, amount);
        member.transfer(amount);
    }

    /// @dev Withdraws the total balance in ETH of the reward for a pool member.
    /// @param poolId Unique id of pool.
    /// @return The amount withdrawn.
    function withdrawTotalRewardForStakingPoolMember(bytes32 poolId)
        external
        returns (uint256)
    {
        // sanity checks
        address payable member = msg.sender;
        uint256 amount = computeRewardBalanceOfStakingPoolMember(poolId, member);

        // update shadow rewards
        shadowRewardsInPoolByOwner[member][poolId] = shadowRewardsInPoolByOwner[member][poolId]._add(amount);
        shadowRewardsByPoolId[poolId] = shadowRewardsByPoolId[poolId]._add(amount);

        // perform withdrawal and return amount withdrawn
        _withdrawFromMemberInStakingPoolRewardVault(poolId, amount);
        member.transfer(amount);
        return amount;
    }

    /// @dev Returns the sum total reward balance in ETH of a staking pool, across all members and the pool operator.
    /// @param poolId Unique id of pool.
    /// @return Balance.
    function getTotalRewardBalanceOfStakingPool(bytes32 poolId)
        external
        view
        returns (uint256)
    {
        return getTotalBalanceInStakingPoolRewardVault(poolId);
    }

    /// @dev Returns the reward balance in ETH of the pool operator.
    /// @param poolId Unique id of pool.
    /// @return Balance.
    function getRewardBalanceOfStakingPoolOperator(bytes32 poolId)
        external
        view
        returns (uint256)
    {
        return getBalanceOfOperatorInStakingPoolRewardVault(poolId);
    }

    /// @dev Returns the reward balance in ETH co-owned by the members of a pool.
    /// @param poolId Unique id of pool.
    /// @return Balance.
    function getRewardBalanceOfStakingPoolMembers(bytes32 poolId)
        external
        view
        returns (uint256)
    {
        return getBalanceOfMembersInStakingPoolRewardVault(poolId);
    }

    /// @dev Returns the shadow balance of a specific member of a staking pool.
    /// @param poolId Unique id of pool.
    /// @param member The member of the pool. 
    /// @return Balance.
    function getShadowBalanceOfStakingPoolMember(bytes32 poolId, address member)
        public
        view
        returns (uint256)
    {
        return shadowRewardsInPoolByOwner[member][poolId];
    }

    /// @dev Returns the total shadow balance of a staking pool.
    /// @param poolId Unique id of pool.
    /// @return Balance.
    function getTotalShadowBalanceOfStakingPool(bytes32 poolId)
        public
        view
        returns (uint256)
    {
        return shadowRewardsByPoolId[poolId];
    }

    /// @dev Computes the reward balance in ETH of a specific member of a pool.
    /// @param poolId Unique id of pool.
    /// @param member The member of the pool. 
    /// @return Balance.
    function computeRewardBalanceOfStakingPoolMember(bytes32 poolId, address member)
        public
        view
        returns (uint256)
    {
        uint256 poolBalance = getBalanceOfMembersInStakingPoolRewardVault(poolId);
        return LibRewardMath._computePayoutDenominatedInRealAsset(
            delegatedStakeToPoolByOwner[member][poolId],
            delegatedStakeByPoolId[poolId],
            shadowRewardsInPoolByOwner[member][poolId],
            shadowRewardsByPoolId[poolId],
            poolBalance
        );
    }

    /// @dev A member joins a staking pool.
    /// This function increments the shadow balance of the member, along
    /// with the total shadow balance of the pool. This ensures that
    /// any rewards belonging to existing members will not be diluted.
    /// @param poolId Unique Id of pool to join.
    /// @param member The member to join. 
    /// @param amountOfStakeToDelegate The stake to be delegated by `member` upon joining.
    /// @param totalStakeDelegatedToPool The amount of stake currently delegated to the pool.
    ///                                  This does not include `amountOfStakeToDelegate`.
    function _joinStakingPool(
        bytes32 poolId,
        address payable member,
        uint256 amountOfStakeToDelegate,
        uint256 totalStakeDelegatedToPool
    )
        internal
    {
        // update delegator's share of reward pool
        uint256 poolBalance = getBalanceOfMembersInStakingPoolRewardVault(poolId);
        uint256 buyIn = LibRewardMath._computeBuyInDenominatedInShadowAsset(
            amountOfStakeToDelegate,
            totalStakeDelegatedToPool,
            shadowRewardsByPoolId[poolId],
            poolBalance
        );

        // the buy-in will be > 0 iff there exists a non-zero reward.
        if (buyIn > 0) {
            shadowRewardsInPoolByOwner[member][poolId] = shadowRewardsInPoolByOwner[member][poolId]._add(buyIn);
            shadowRewardsByPoolId[poolId] = shadowRewardsByPoolId[poolId]._add(buyIn);
        }
    }

    /// @dev A member leaves a staking pool.
    /// This function decrements the shadow balance of the member, along
    /// with the total shadow balance of the pool. This ensures that
    /// any rewards belonging to co-members will not be inflated.
    /// @param poolId Unique Id of pool to leave.
    /// @param member The member to leave. 
    /// @param amountOfStakeToUndelegate The stake to be undelegated by `member` upon leaving.
    /// @param totalStakeDelegatedToPoolByMember The amount of stake currently delegated to the pool by the member.
    ///                                          This includes `amountOfStakeToUndelegate`.
    /// @param totalStakeDelegatedToPool The total amount of stake currently delegated to the pool, across all members.
    ///                                  This includes `amountOfStakeToUndelegate`.
    function _leaveStakingPool(
        bytes32 poolId,
        address payable member,
        uint256 amountOfStakeToUndelegate,
        uint256 totalStakeDelegatedToPoolByMember,
        uint256 totalStakeDelegatedToPool
    )
        internal
    {
         // get payout
        uint256 poolBalance = getBalanceOfMembersInStakingPoolRewardVault(poolId);
        uint256 payoutInRealAsset = 0;
        uint256 payoutInShadowAsset = 0;
        if (totalStakeDelegatedToPoolByMember == amountOfStakeToUndelegate) {
            // full payout; this is computed separately to avoid extra computation and rounding.
            payoutInShadowAsset = shadowRewardsInPoolByOwner[member][poolId];
            payoutInRealAsset = LibRewardMath._computePayoutDenominatedInRealAsset(
                amountOfStakeToUndelegate,
                totalStakeDelegatedToPool,
                payoutInShadowAsset,
                shadowRewardsByPoolId[poolId],
                poolBalance
            );
        } else {
            // partial payout
            (payoutInRealAsset, payoutInShadowAsset) = LibRewardMath._computePartialPayout(
                amountOfStakeToUndelegate,
                totalStakeDelegatedToPoolByMember,
                totalStakeDelegatedToPool,
                shadowRewardsInPoolByOwner[member][poolId],
                shadowRewardsByPoolId[poolId],
                poolBalance
            );
        }

        // update shadow rewards
        shadowRewardsInPoolByOwner[member][poolId] = shadowRewardsInPoolByOwner[member][poolId]._sub(payoutInShadowAsset);
        shadowRewardsByPoolId[poolId] = shadowRewardsByPoolId[poolId]._sub(payoutInShadowAsset);

        // withdraw payout for member
        if (payoutInRealAsset > 0) {
            _withdrawFromMemberInStakingPoolRewardVault(poolId, payoutInRealAsset);
            member.transfer(payoutInRealAsset);
        }
    }
}
