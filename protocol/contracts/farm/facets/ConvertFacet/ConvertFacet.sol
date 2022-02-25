/**
 * SPDX-License-Identifier: MIT
**/

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import "./ConvertSilo.sol";
import "../../../libraries/LibConvert.sol";
import "../../../libraries/LibInternal.sol";
import "../../../libraries/LibClaim.sol";

/**
 * @author Publius
 * @title Silo handles depositing and withdrawing Beans and LP, and updating the Silo.
**/
contract ConvertFacet is ConvertSilo {

    using SafeMath for uint256;
    using SafeMath for uint32;

    // function convert(
    //     bytes calldata userData,
    //     uint32[] memory crates,
    //     uint256[] memory amounts,
    //     bool partialUpdateSilo
    // )
    //     external 
    // {
    //     LibInternal.updateSilo(msg.sender, partialUpdateSilo);

    //     (   
    //         address toToken,
    //         address fromToken,
    //         uint256 toTokenAmount,
    //         uint256 fromTokenAmount,
    //         uint256 bdv
    //     ) = LibConvert.convert(userData);

    //     (
    //         uint256 tokensRemoved,
    //         uint256 stalkRemoved
    //     ) = _withdrawTokensForConvert(fromToken, crates, amounts, fromTokenAmount);

    //     _depositTokens(toToken, toTokenAmount, bdv, stalkRemoved);
    //     LibSilo.updateBalanceOfRainStalk(msg.sender);
    // }  

    function convertDepositedBeans(
        bytes calldata userData,
        uint32[] memory crates,
        uint256[] memory amounts,
        bool partialUpdateSilo
    )
        external 
    {
        LibInternal.updateSilo(msg.sender, partialUpdateSilo);
        (uint256 lp, uint256 beansConverted) = LibConvert.sellToPegAndAddLiquidity(userData);
        (uint256 beansRemoved, uint256 stalkRemoved) = _withdrawBeansForConvert(crates, amounts, beansConverted);
        require(beansRemoved == beansConverted, "Silo: Wrong Beans removed.");
        uint32 _s = uint32(stalkRemoved.div(beansConverted.mul(C.getSeedsPerLPBean())));
        _s = getDepositSeason(_s);

        _depositLP(lp, beansConverted, _s);
        LibCheck.balanceCheck();
        LibSilo.updateBalanceOfRainStalk(msg.sender);
    }   

    function convertDepositedLP(
        bytes calldata userData,
        uint32[] memory crates,
        uint256[] memory amounts,
        bool partialUpdateSilo
    )
        external
    {
        LibInternal.updateSilo(msg.sender, partialUpdateSilo);
        (uint256 beans, uint256 lpConverted) = LibConvert.removeLPAndBuyToPeg(userData);
        (uint256 lpRemoved, uint256 stalkRemoved) = _withdrawLPForConvert(crates, amounts, lpConverted);
        require(lpRemoved == lpConverted, "Silo: Wrong LP removed.");
        uint32 _s = uint32(stalkRemoved.div(beans.mul(C.getSeedsPerBean())));
        _s = getDepositSeason(_s);
        _depositBeans(beans, _s);
        LibCheck.balanceCheck();
        LibSilo.updateBalanceOfRainStalk(msg.sender);
    }

    function claimConvertAddAndDepositLP(
        uint256 lp,
        LibMarket.AddLiquidity calldata al,
        uint32[] memory crates,
        uint256[] memory amounts,
        bool partialUpdateSilo,
        LibClaim.Claim calldata claim
    )
        external
        payable
    {
        LibClaim.claim(partialUpdateSilo, claim);
        _convertAddAndDepositLP(lp, al, crates, amounts, partialUpdateSilo);
    }

    function convertAddAndDepositLP(
        uint256 lp,
        LibMarket.AddLiquidity calldata al,
        uint32[] memory crates,
        uint256[] memory amounts,
        bool partialUpdateSilo
    )
        public
        payable
    {
        _convertAddAndDepositLP(lp, al, crates, amounts, partialUpdateSilo);
    }

    function lpToPeg() external view returns (uint256 lp) {
        return LibConvert.lpToPeg();
    }

    function beansToPeg() external view returns (uint256 beans) {
        (uint256 ethReserve, uint256 beanReserve) = reserves();
        return LibConvert.beansToPeg(ethReserve, beanReserve);
    }

    function getDepositSeason(uint32 _s) internal view returns (uint32) {
        uint32 __s = season();
        if (_s >= __s) _s = __s - 1;
        return uint32(__s.sub(_s));
    }
}
