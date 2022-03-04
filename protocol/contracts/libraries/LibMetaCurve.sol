/**
 * SPDX-License-Identifier: MIT
**/

pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import "../C.sol";

interface I3Curve {
    function get_virtual_price() external view returns (uint256);
}

library LibMetaCurve {
    using SafeMath for uint256;

    uint256 private constant A_PRECISION = 100;
    address private constant POOL = address(0x3a70DfA7d2262988064A2D051dd47521E43c9BdD);
    address private constant CRV3_POOL = address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    uint256 private constant N_COINS  = 2;
    uint256 private constant RATE_MULTIPLIER = 1e12; // Bean has 6 Decimals
    uint256 private constant PRECISION = 1e18;
    uint256 private constant i = 0;
    uint256 private constant j = 1;

    function balances() internal view returns (uint256[2] memory balances) {
        balances = C.curveMetapool().get_balances();
    }

    function rateMultiplier() internal pure returns (uint256) {
        return RATE_MULTIPLIER;
    }

    function virtualPrice() internal view returns (uint256[2] memory balances) {
        balances = C.curveMetapool().get_balances();
    }

    function bdv(uint256 amount) internal view returns (uint256) {
        uint256[2] memory balances = C.curveMetapool().get_balances();
        uint256 totalSupply = C.curveMetapool().totalSupply();
        uint256[2] memory xp = getXP(balances);
        uint256 price = getPrice(xp);
        uint256 beanValue = balances[0].mul(amount).div(totalSupply);
        uint256 curveValue = xp[1].mul(amount).div(totalSupply).div(price);
        return beanValue.add(curveValue);
    }
    
    function getPrice(uint256[2] memory xp) private view returns (uint) {
        uint256 x = xp[i] + RATE_MULTIPLIER;
        uint256 y = getY(x, xp);
        uint256 dy = xp[j] - y - 1;
        return dy;
    }

    function getY(uint256 x, uint256[2] memory xp) private view returns (uint256) {
        // Solution is taken from pool contract: 0x3a70DfA7d2262988064A2D051dd47521E43c9BdD
        uint256 a = C.curveMetapool().A_precise();
        uint256 D = getD(xp, a);
        uint256 S_ = 0;
        uint256 _x = 0;
        uint256 y_prev = 0;
        uint256 c = D;
        uint256 Ann = a * N_COINS;

        for (uint256 _i = 0; _i < N_COINS; _i++) {
            if (_i == i) _x = x;
            else if (_i != j) _x = xp[_i];
            else continue;
            S_ += _x;
            c = c * D / (_x * N_COINS);
        }

        c = c * D * A_PRECISION / (Ann * N_COINS);
        uint256 b = S_ + D * A_PRECISION / Ann; // - D
        uint256 y = D;

        for (uint256 _i = 0; _i < 255; _i++) {
            y_prev = y;
            y = (y*y + c) / (2 * y + b - D);
            if (y > y_prev && y - y_prev <= 1) return y;
            else if (y_prev - y <= 1) return y;
        }
        require(false, "Price: Convergence false");
    }

    function getDFromBalances(uint256[2] memory balances) internal view returns (uint) {
        return getD(getXP(balances), C.curveMetapool().A_precise());
    }

    function getD(uint256[2] memory xp, uint256 a) private pure returns (uint D) {
        // Solution is taken from pool contract: 0x3a70DfA7d2262988064A2D051dd47521E43c9BdD
        uint256 S;
        uint256 Dprev;
        for (uint _i = 0; _i < xp.length; _i++) {
            S += xp[_i];
        }
        if (S == 0) return 0;

        D = S;
        uint256 Ann = a * N_COINS;
        for (uint _i = 0; _i < 256; _i++) {
            uint256 D_P = D;
            for (uint _j = 0; _j < xp.length; _j++) {
                D_P = D_P * D / (xp[_j] * N_COINS);
            }
            Dprev = D;
            D = (Ann * S / A_PRECISION + D_P * N_COINS) * D / ((Ann - A_PRECISION) * D / A_PRECISION + (N_COINS + 1) * D_P);
            if (D > Dprev && D - Dprev <= 1) return D;
            else if (Dprev - D <= 1) return D;
        }
        require(false, "Price: Convergence false");
        return 0;
    }

    function getXP(uint256[2] memory balances) internal view returns (uint256[2] memory xp) {
        xp[0] = balances[0].mul(RATE_MULTIPLIER);
        xp[1] = balances[1].mul(I3Curve(CRV3_POOL).get_virtual_price()).div(PRECISION);
    }

    function currentPrice() internal view returns (uint256) {
        uint256[2] memory balances = C.curveMetapool().get_balances();
        uint256 totalSupply = C.curveMetapool().totalSupply();
        uint256[2] memory xp = getXP(balances);
        uint256 price = getPrice(xp);
    }

    function removeLiquidityOneCoin(
        uint256 _token_amount,
        uint8 i,
        uint256 min_amount
    )
        internal returns (uint256 coin_amount_received) 
    {
        coin_amount_received = C.curveMetapool().remove_liquidity_one_coin(_token_amount, i, min_amount);
    }

    function addLiquidity(uint256[] memory amounts, uint256 min_mint_amount) internal returns (uint256 lp_added) {
        lp_added = C.curveMetapool().add_liquidity(amounts, min_mint_amount);
    }
    
    function getPrice(uint256[2] memory balances, uint256[2] memory rates) private view returns (uint price) {
        uint256[2] memory balances = C.curveMetapool().get_balances();
        uint256 totalSupply = C.curveMetapool().totalSupply();
        uint256[2] memory xp = getXP(balances);
        price = getPrice(xp);
    }

    function totalSupply() internal returns (uint256) {
        return C.curveMetapool().totalSupply();
    }
}
