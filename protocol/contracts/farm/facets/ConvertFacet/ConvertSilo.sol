/**
 * SPDX-License-Identifier: MIT
**/

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import "../../../libraries/Silo/LibSilo.sol";
import "../../../libraries/Silo/LibBeanSilo.sol";
import "../../../libraries/Silo/LibTokenSilo.sol";
import "../../../libraries/LibCheck.sol";
import "../../../libraries/LibInternal.sol";
import "../../../libraries/LibMarket.sol";
import "../../../C.sol";
import "../Utils/ToolShed.sol";

/**
 * @author Publius
 * @title Bean Silo
**/
contract ConvertSilo is ToolShed {

    AppStorage internal s;

    using SafeMath for uint256;
    using SafeMath for uint32;
    
    event TokenDeposit(address indexed token, address indexed account, uint256 season, uint256 lp, uint256 seeds);
    event TokenRemove(address indexed token, address indexed account, uint32[] crates, uint256[] crateLP, uint256 lp);
    event BeanRemove(address indexed account, uint32[] crates, uint256[] crateBeans, uint256 beans);

    struct WithdrawState {
        uint256 newLP;
        uint256 beansAdded;
        uint256 beansTransferred;
        uint256 beansRemoved;
        uint256 stalkRemoved;
        uint256 i;
    }

    function _convertAddAndDepositLP(
        address token,
        uint256 lp,
        LibMarket.AddLiquidity calldata al,
        uint32[] memory crates,
        uint256[] memory amounts,
       	bool toInternalBalance
    )
        internal
    {
	LibInternal.updateSilo(msg.sender);
        WithdrawState memory w;
        if (bean().balanceOf(address(this)) < al.beanAmount) {
            	w.beansTransferred = al.beanAmount.sub(s.bean.deposited);
            	bean().transferFrom(msg.sender, address(this), w.beansTransferred);
        }
        (w.beansAdded, w.newLP) = LibMarket.addLiquidity(al); // w.beansAdded is beans added to LP
        require(w.newLP > 0, "Silo: No LP added.");
        (w.beansRemoved, w.stalkRemoved) = _withdrawBeansForConvert(crates, amounts, w.beansAdded); // w.beansRemoved is beans removed from Silo
        uint256 amountFromWallet = w.beansAdded.sub(w.beansRemoved, "Silo: Removed too many Beans.");

        if (amountFromWallet < w.beansTransferred) {
            bean().transfer(msg.sender, w.beansTransferred.sub(amountFromWallet));
	    } else if (w.beansTransferred < amountFromWallet) {
            uint256 transferAmount = amountFromWallet.sub(w.beansTransferred);
            LibMarket.allocatedBeans(transferAmount);
        }

        w.i = w.stalkRemoved.div(LibTokenSilo.beanDenominatedValue(token, lp.add(w.newLP)), "Silo: No LP Beans.");
        uint32 depositSeason = uint32(season().sub(w.i.div(s.ss[token].seeds)));

        if (lp > 0) pair().transferFrom(msg.sender, address(this), lp);
	
        lp = lp.add(w.newLP);
        _deposit(token, depositSeason, lp, LibTokenSilo.beanDenominatedValue(token, lp), toInternalBalance);
        LibCheck.beanBalanceCheck();
        LibSilo.updateBalanceOfRainStalk(msg.sender);
    }

    function _convertDepositedBeansAndCirculatingStalkSeed(
        address token,
        uint256 beans,
        uint32[] memory crates,
        uint256[] memory amounts,
       	bool toInternalBalance,
        bool fromInternalBalance
    )
        internal
    {
	    // LibInternal.updateSilo(msg.sender);
        // WithdrawState memory w;
        // // (w.beansAdded, w.newLP) = LibMarket.addLiquidity(al); // w.beansAdded is beans added to LP
        
        // // require(w.newLP > 0, "Silo: No LP added.");
        // (w.beansRemoved, w.stalkRemoved) = __withdrawBeansForConvert(crates, amounts, beans); // w.beansRemoved is beans removed from Silo
        // uint256 stalk_to_remove = w.stalkRemoved;
        // // Because we have not withdrawn the silo assets yet, we must account for the actual stalk removed here
        // w.stalkRemoved = w.stalkRemoved.sub(w.beansRemoved.mul(C.getStalkPerBean()));

        // w.i = w.stalkRemoved.div(LibTokenSilo.beanDenominatedValue(token, lp.add(w.newLP)), "Silo: No LP Beans.");
        // uint32 depositSeason = uint32(season().sub(w.i.div(s.ss[token].seeds)));
	
        // lp = lp.add(w.newLP);
        // (w.grossAddedStalk, w.grossAddedSeeds) = __deposit(token, depositSeason, lp, LibTokenSilo.beanDenominatedValue(s.c.pair, lp));
        // // Net Total Up Actual Deposited/Withdrawn Stalk and Seeds
        // w.netStalk = int256(w.grossAddedStalk) - int256(stalk_to_remove);
        // w.netSeeds = int256(w.grossAddedSeeds) - int256(w.beansRemoved.mul(C.getSeedsPerBean()));
        // // Increment and Decrement Silo Assets
        // LibSilo.convertSiloAssets(msg.sender, w.netSeeds,  w.netStalk, toInternalBalance, fromInternalBalance);
        
        // LibCheck.beanBalanceCheck();
        // LibSilo.updateBalanceOfRainStalk(msg.sender);
    }

    /**
     * Internal LP
    **/

    function __deposit(
        address token,
        uint32 _s, 
        uint256 amount, 
        uint256 lpb
    ) 
        internal 
        returns(uint256 stalk_to_deposit, uint256 seeds_to_deposit) 
    {
        LibTokenSilo.depositWithBDV(msg.sender, token, _s, amount, lpb);
        uint256 seeds_to_deposit = lpb.mul(s.ss[token].seeds);
        uint256 stalk_to_deposit = lpb.mul(s.ss[token].stalk);
        if (_s > 0) stalk_to_deposit = stalk_to_deposit.add((season().sub(_s)).mul(seeds_to_deposit));
    }

    function _deposit(address token, uint32 _s, uint256 amount, uint256 lpb, bool toInternalBalance) internal {
        (uint256 stalk, uint256 seeds) = __deposit(token, _s, amount, lpb);
        LibSilo.depositSiloAssets(msg.sender, seeds, stalk, toInternalBalance);
    }

    function _withdrawForConvert(
        address token,
        uint32[] memory crates,
        uint256[] memory amounts,
        uint256 maxLP,
        bool fromInternalBalance
    )
        internal
        returns (uint256 stalkRemoved)
    {
        require(crates.length == amounts.length, "Silo: Crates, amounts are diff lengths.");
        uint256 bdvRemoved;
        uint256 lpRemoved;
        uint256 depositLP;
        uint256 depositedBDV;
        uint256 i = 0;
        while ((i < crates.length) && (lpRemoved < maxLP)) {
            if (lpRemoved.add(amounts[i]) < maxLP)
                (depositLP, depositedBDV) = LibTokenSilo.removeDeposit(msg.sender, token, crates[i], amounts[i]);
            else
                (depositLP, depositedBDV) = LibTokenSilo.removeDeposit(msg.sender, token, crates[i], maxLP.sub(lpRemoved));
            lpRemoved = lpRemoved.add(depositLP);
            bdvRemoved = bdvRemoved.add(depositedBDV);
            stalkRemoved = stalkRemoved.add(LibSilo.stalkReward(depositedBDV.mul(s.ss[token].seeds), season()-crates[i]));
            i++;
        }
        if (i > 0) amounts[i.sub(1)] = depositLP;
        while (i < crates.length) {
            amounts[i] = 0;
            i++;
        }
        LibTokenSilo.decrementDepositedToken(token, lpRemoved);
        LibSilo.withdrawSiloAssets(msg.sender, bdvRemoved.mul(s.ss[token].seeds), stalkRemoved.add(bdvRemoved.mul(s.ss[token].stalk)), fromInternalBalance);
        emit TokenRemove(token, msg.sender, crates, amounts, lpRemoved);
    }

    /**
     * Internal Bean
    **/

    function _depositBeans(uint256 amount, uint32 _s, bool toInternalBalance) internal {
        require(amount > 0, "Silo: No beans.");
        LibBeanSilo.incrementDepositedBeans(amount);
        uint256 stalk = amount.mul(C.getStalkPerBean());
        uint256 seeds = amount.mul(C.getSeedsPerBean());
        if (_s < season()) stalk = stalk.add(LibSilo.stalkReward(seeds, season()-_s));
        LibSilo.depositSiloAssets(msg.sender, seeds, stalk, toInternalBalance);
        LibBeanSilo.addBeanDeposit(msg.sender, _s, amount);
        LibCheck.beanBalanceCheck();
    }

    function _withdrawBeansForConvert(
        uint32[] memory crates,
        uint256[] memory amounts,
        uint256 maxBeans
    )
        internal
        returns (uint256 beansRemoved, uint256 stalkRemoved)
    {
        require(crates.length == amounts.length, "Silo: Crates, amounts are diff lengths.");
        uint256 crateBeans;
        uint256 i = 0;
        while ((i < crates.length) && (beansRemoved < maxBeans)) {
            if (beansRemoved.add(amounts[i]) < maxBeans)
                crateBeans = LibBeanSilo.removeBeanDeposit(msg.sender, crates[i], amounts[i]);
            else
                crateBeans = LibBeanSilo.removeBeanDeposit(msg.sender, crates[i], maxBeans.sub(beansRemoved));
            beansRemoved = beansRemoved.add(crateBeans);
            stalkRemoved = stalkRemoved.add(crateBeans.mul(C.getStalkPerBean()).add(
                LibSilo.stalkReward(crateBeans.mul(C.getSeedsPerBean()), season()-crates[i]
            )));
            i++;
        }
        if (i > 0) amounts[i.sub(1)] = crateBeans;
        while (i < crates.length) {
            amounts[i] = 0;
            i++;
        }
        LibBeanSilo.decrementDepositedBeans(beansRemoved);
        LibSilo.withdrawSiloAssets(msg.sender, beansRemoved.mul(C.getSeedsPerBean()), stalkRemoved, true);
        stalkRemoved = stalkRemoved.sub(beansRemoved.mul(C.getStalkPerBean()));
        emit BeanRemove(msg.sender, crates, amounts, beansRemoved);
        return (beansRemoved, stalkRemoved);
    }

    function reserves() internal view returns (uint256, uint256) {
        (uint112 reserve0, uint112 reserve1,) = pair().getReserves();
        return (s.index == 0 ? reserve1 : reserve0,s.index == 0 ? reserve0 : reserve1);
    }

    function pair() internal view returns (IUniswapV2Pair) {
        return IUniswapV2Pair(s.c.pair);
    }

    function bean() internal view returns (IBean) {
        return IBean(s.c.bean);
    }

    function season() internal view returns (uint32) {
        return s.season.current;
    }
}