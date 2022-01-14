/**
 * SPDX-License-Identifier: MIT
**/

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import "./UpdateSilo.sol";
import "../../../libraries/Silo/LibTokenSilo.sol";

/**
 * @author Publius
 * @title Token Silo
**/
contract TokenSilo is UpdateSilo {

    using SafeMath for uint256;
    using SafeMath for uint32;

    event LPDeposit(address indexed account, uint256 season, uint256 lp, uint256 seeds);
    event LPRemove(address indexed account, uint32[] crates, uint256[] crateLP, uint256 lp);
    event LPWithdraw(address indexed account, uint256 season, uint256 lp);

    /**
     * Getters
    **/

    function totalDepositedLP() public view returns (uint256) {
            return s.lp.deposited;
    }

    function totalWithdrawnLP() public view returns (uint256) {
            return s.lp.withdrawn;
    }

    function lpDeposit(address account, uint32 id, address lp_address) public view returns (uint256, uint256) {
        return (s.a[account].deposits[IERC20(lp_address)][id].tokens, s.a[account].deposits[IERC20(lp_address)][id].seeds);
    }

    function lpWithdrawal(address account, uint32 i, address lp_address) public view returns (uint256) {
        return s.a[account].withdrawals[IERC20(lp_address)][i];
    }

    // V2 For All Token Types
    function totalDepositedToken(address token) public view returns (uint256) {
        return s.siloBalances[IERC20(token)].deposited;
    }

    function totalWithdrawnToken(address token) public view returns (uint256) {
        return s.siloBalances[IERC20(token)].withdrawn;
    }

    /**
     * Internal
    **/

    function _depositLP(address lp_address, uint256 amount) internal {
        updateSilo(msg.sender);
        uint32 _s = season();
        uint256 lpb = LibTokenSilo.beanDenominatedValue(lp_address, amount);
        require(lpb > 0, "Silo: No Beans under LP.");
        LibTokenSilo.incrementDepositedToken(lp_address, amount);
        uint256 seeds = lpb.mul(s.seedsPerBDV[lp_address]);
        if (season() == _s) LibSilo.depositSiloAssets(msg.sender, seeds, lpb.mul(10000));
        else LibSilo.depositSiloAssets(msg.sender, seeds, lpb.mul(10000).add(season().sub(_s).mul(seeds)));

        LibTokenSilo.addDeposit(lp_address, msg.sender, _s, amount, lpb.mul(s.seedsPerBDV[lp_address]));
        
        // Must rewrite this to take into account different lp pools
        LibCheck.lpBalanceCheck();
    }

    function _withdraw(address lp_address, uint32[] calldata crates, uint256[] calldata amounts) internal {
        updateSilo(msg.sender);
        require(crates.length == amounts.length, "Silo: Crates, amounts are diff lengths.");
        (
            uint256 lpRemoved,
            uint256 stalkRemoved,
            uint256 seedsRemoved
        ) = removeLPDeposits(lp_address, crates, amounts);
        uint32 arrivalSeason = season() + s.season.withdrawBuffer;
        addTokenWithdrawal(lp_address, msg.sender, arrivalSeason, lpRemoved);
        LibTokenSilo.decrementDepositedToken(lp_address, lpRemoved);
        LibSilo.withdrawSiloAssets(msg.sender, seedsRemoved, stalkRemoved);
        LibSilo.updateBalanceOfRainStalk(msg.sender);
    }

    function _withdrawLP(address lp_address, uint32[] calldata crates, uint256[] calldata amounts) internal {
        updateSilo(msg.sender);
        require(crates.length == amounts.length, "Silo: Crates, amounts are diff lengths.");
        (
            uint256 lpRemoved,
            uint256 stalkRemoved,
            uint256 seedsRemoved
        ) = removeLPDeposits(lp_address, crates, amounts);
        uint32 arrivalSeason = season() + s.season.withdrawBuffer;
        addTokenWithdrawal(lp_address, msg.sender, arrivalSeason, lpRemoved);
        LibTokenSilo.decrementDepositedToken(lp_address, lpRemoved);
        LibSilo.withdrawSiloAssets(msg.sender, seedsRemoved, stalkRemoved);
        LibSilo.updateBalanceOfRainStalk(msg.sender);

        // Need to generalize this LibCheck function possibly using function selectors
        LibCheck.lpBalanceCheck();
    }

    function removeLPDeposits(address lp_address, uint32[] calldata crates, uint256[] calldata amounts)
        private
        returns (uint256 lpRemoved, uint256 stalkRemoved, uint256 seedsRemoved)
    {
        for (uint256 i = 0; i < crates.length; i++) {
            (uint256 crateBeans, uint256 crateSeeds) = LibTokenSilo.removeDeposit(
                lp_address,
                msg.sender,
                crates[i],
                amounts[i]
            );
            lpRemoved = lpRemoved.add(crateBeans);
            stalkRemoved = stalkRemoved.add(crateSeeds.mul(C.getStalkPerLPSeed()).add(
                LibSilo.stalkReward(crateSeeds, season()-crates[i]))
            );
            seedsRemoved = seedsRemoved.add(crateSeeds);
        }
        emit LPRemove(msg.sender, crates, amounts, lpRemoved);
    }

    function addTokenWithdrawal(address token, address account, uint32 arrivalSeason, uint256 amount) private {
        s.a[account].withdrawals[IERC20(token)][arrivalSeason] = s.a[account].withdrawals[IERC20(token)][arrivalSeason].add(amount);
        s.siloBalances[IERC20(token)].withdrawn = s.siloBalances[IERC20(token)].withdrawn.add(amount);
        emit LPWithdraw(msg.sender, arrivalSeason, amount);
    }

    function pair() internal view returns (IUniswapV2Pair) {
        return IUniswapV2Pair(s.c.pair);
    }
}