/**
 * SPDX-License-Identifier: MIT
 **/

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import "~/libraries/LibBytes.sol";
import "../LibAppStorage.sol";
import "../../C.sol";
import "./LibUnripeSilo.sol";
import "./LibTokenSilo.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/SafeCast.sol";
import "~/libraries/LibSafeMathSigned128.sol";
import "hardhat/console.sol";

/**
 * @title LibLegacyTokenSilo
 * @author Publius
 * @notice Contains functions for depositing, withdrawing and claiming
 * whitelisted Silo tokens.
 *
 * For functionality related to Seeds, Stalk, and Roots, see {LibSilo}.
 */
library LibLegacyTokenSilo {
    using SafeMath for uint256;
    using SafeMath for uint32;
    using SafeCast for uint256;
    using LibSafeMathSigned128 for int128;


    //important to note that this event is only here for unit tests purposes of legacy code and to ensure unripe all works with new bdv system
    event AddDeposit(
        address indexed account,
        address indexed token,
        uint32 season,
        uint256 amount,
        uint256 bdv
    );


    //////////////////////// ACCOUNTING: TOTALS ////////////////////////
    
    /**
     * @dev Increment the total amount of `token` deposited in the Silo.
     */
    function incrementTotalDeposited(address token, uint256 amount) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.siloBalances[token].deposited = s.siloBalances[token].deposited.add(
            amount
        );
    }

    /**
     * @dev Decrement the total amount of `token` deposited in the Silo.
     */
    function decrementTotalDeposited(address token, uint256 amount) internal {
        AppStorage storage s = LibAppStorage.diamondStorage();
        s.siloBalances[token].deposited = s.siloBalances[token].deposited.sub(
            amount
        );
    }


    //////////////////////// REMOVE DEPOSIT ////////////////////////

    /**
     * @dev Remove `amount` of `token` from a user's Deposit in `season`.
     *
     * A "Crate" refers to the existing Deposit in storage at:
     *  `s.a[account].legacyDeposits[token][season]`
     *
     * Partially removing a Deposit should scale its BDV proportionally. For ex.
     * removing 80% of the tokens from a Deposit should reduce its BDV by 80%.
     *
     * During an update, `amount` & `bdv` are cast uint256 -> uint128 to
     * optimize storage cost, since both values can be packed into one slot.
     *
     * This function DOES **NOT** EMIT a {RemoveDeposit} event. This
     * asymmetry occurs because {removeDepositFromAccount} is called in a loop
     * in places where multiple deposits are removed simultaneously, including
     * {TokenSilo-removeDepositsFromAccount} and {TokenSilo-_transferDeposits}.
     */
    function removeDepositFromAccount(
        address account,
        address token,
        uint32 season,
        uint256 amount
    ) internal returns (uint256 crateBDV) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        uint256 crateAmount;
        (crateAmount, crateBDV) = (
            s.a[account].legacyDeposits[token][season].amount,
            s.a[account].legacyDeposits[token][season].bdv
        );

        // Partial remove
        if (amount < crateAmount) {
            uint256 removedBDV = amount.mul(crateBDV).div(crateAmount);
            uint256 updatedBDV = uint256(
                s.a[account].legacyDeposits[token][season].bdv
            ).sub(removedBDV);
            uint256 updatedAmount = uint256(
                s.a[account].legacyDeposits[token][season].amount
            ).sub(amount);

            require(
                updatedBDV <= uint128(-1) && updatedAmount <= uint128(-1),
                "Silo: uint128 overflow."
            );

            s.a[account].legacyDeposits[token][season].amount = uint128(
                updatedAmount
            );
            s.a[account].legacyDeposits[token][season].bdv = uint128(
                updatedBDV
            );

            return removedBDV;
        }

        // Full remove
        if (crateAmount > 0) delete s.a[account].legacyDeposits[token][season];

        // Excess remove
        // This can only occur for Unripe Beans and Unripe LP Tokens, and is a
        // result of using Silo V1 storage slots to store Unripe BEAN/LP
        // Deposit information. See {AppStorage.sol:Account-State}.
        if (amount > crateAmount) {
            amount -= crateAmount;
            if (LibUnripeSilo.isUnripeBean(token))
                return
                    crateBDV.add(
                        LibUnripeSilo.removeUnripeBeanDeposit(
                            account,
                            season,
                            amount
                        )
                    );
            else if (LibUnripeSilo.isUnripeLP(token))
                return
                    crateBDV.add(
                        LibUnripeSilo.removeUnripeLPDeposit(
                            account,
                            season,
                            amount
                        )
                    );
            revert("Silo: Crate balance too low.");
        }
    }

    //////////////////////// GETTERS ////////////////////////



    /**
     * @dev Calculate the BDV ("Bean Denominated Value") for `amount` of `token`.
     * 
     * Makes a call to a BDV function defined in the SiloSettings for this 
     * `token`. See {AppStorage.sol:Storage-SiloSettings} for more information.
     */
    // function beanDenominatedValue(address token, uint256 amount)
    //     internal
    //     returns (uint256 bdv)
    // {
    //     AppStorage storage s = LibAppStorage.diamondStorage();

    //     // BDV functions accept one argument: `uint256 amount`
    //     bytes memory callData = abi.encodeWithSelector(
    //         s.ss[token].selector,
    //         amount
    //     );

    //     (bool success, bytes memory data) = address(this).call(
    //         callData
    //     );

    //     if (!success) {
    //         if (data.length == 0) revert();
    //         assembly {
    //             revert(add(32, data), mload(data))
    //         }
    //     }

    //     assembly {
    //         bdv := mload(add(data, add(0x20, 0)))
    //     }
    // }

    /**
     * @dev Locate the `amount` and `bdv` for a user's Deposit in storage.
     *
     * Silo V2 Deposits are stored within each {Account} as a mapping of:
     *  `address token => uint32 season => { uint128 amount, uint128 bdv }`
     *
     * Unripe BEAN and Unripe LP are handled independently so that data
     * stored in the legacy Silo V1 format and the new Silo V2 format can
     * be appropriately merged. See {LibUnripeSilo} for more information.
     *
     * FIXME(naming): rename to `getDeposit()`?
     */
    function tokenDeposit(
        address account,
        address token,
        uint32 season
    ) internal view returns (uint128, uint128) {
        AppStorage storage s = LibAppStorage.diamondStorage();

        if (LibUnripeSilo.isUnripeBean(token)){
            (uint256 amount, uint256 bdv) = LibUnripeSilo.unripeBeanDeposit(account, season);
            return (uint128(amount), uint128(bdv));
        }
        if (LibUnripeSilo.isUnripeLP(token)){
            (uint256 amount, uint256 bdv) = LibUnripeSilo.unripeLPDeposit(account, season);
            return (uint128(amount), uint128(bdv));
        }

        return (
            s.a[account].legacyDeposits[token][season].amount,
            s.a[account].legacyDeposits[token][season].bdv
        );
    }

    /**
     * @notice Returns the balance of Grown Stalk for `account`. Grown Stalk is 
     * earned each Season from Seeds and must be Mown via `SiloFacet-mow` to 
     * apply it to a user's balance.
     * @dev The balance of Grown Stalk for an account can be calculated as:
     *
     * ```
     * elapsedSeasons = currentSeason - lastUpdatedSeason
     * grownStalk = balanceOfSeeds * elapsedSeasons
     * ```
     */
    //TODOSEEDS calculate only up until the stems deployment season
    function balanceOfGrownStalkUpToStemsDeployment(address account)
        internal
        view
        returns (uint256)
    {
        AppStorage storage s = LibAppStorage.diamondStorage();

        console.log('balanceOfGrownStalkUpToStemsDeployment s.season.stemStartSeason: ', s.season.stemStartSeason);
        console.log('balanceOfGrownStalkUpToStemsDeployment s.a[account].lastUpdate: ', s.a[account].lastUpdate);

        // uint256 reward = stalkReward(
        //         s.a[account].s.seeds,
        //         s.season.stemStartSeason - s.a[account].lastUpdate
        //     );
        // console.log('balanceOfGrownStalkUpToStemsDeployment reward: ', reward);

        uint32 stemStartSeason = uint32(s.season.stemStartSeason);

        return
            stalkReward(
                s.a[account].s.seeds,
                s.a[account].lastUpdate-stemStartSeason
            );
    }

    /**
     * @param seeds The number of Seeds held.
     * @param seasons The number of Seasons that have elapsed.
     *
     * @dev Calculates the Stalk that has Grown from a given number of Seeds
     * over a given number of Seasons.
     *
     * Each Seed yields 1E-4 (0.0001, or 1 / 10_000) Stalk per Season.
     *
     * Seasons is measured to 0 decimals. There are no fractional Seasons.
     * Seeds are measured to 6 decimals.
     * Stalk is measured to 10 decimals.
     * 
     * Example:
     *  - `seeds = 1E6` (1 Seed)
     *  - `seasons = 1` (1 Season)
     *  - The result is `1E6 * 1 = 1E6`. Since Stalk is measured to 10 decimals,
     *    this is `1E6/1E10 = 1E-4` Stalk.
     */
    function stalkReward(uint256 seeds, uint32 seasons)
        internal
        view //TODOSEEDS cahnge back to pure
        returns (uint256)
    {
        console.log('stalkReward: seeds ', seeds);
        console.log('stalkReward: seasons ', seasons);
        return seeds.mul(seasons);
    }

    function isDepositSeason(uint256 seedsPerBdv, int128 stem)
        internal
        pure
        returns (bool)
    {
        if (seedsPerBdv == 0) {
            return false; //shortcut since we know it's a newer token?
        }

        return
            stem <= 0 && //old deposits in seasons will have a negative grown stalk per bdv
            uint256(-stem) % seedsPerBdv == 0;
    }

    function seasonToStem(uint256 seedsPerBdv, uint32 season)
        internal
        view
        returns (int128 stem)
    {
        AppStorage storage s = LibAppStorage.diamondStorage();
        
        require(seedsPerBdv > 0, "Silo: Token not supported");

        //need to go back in time, calculate the delta between the current season and that old deposit season,
        //and that's how many seasons back we need to go. Then, multiply that by seedsPerBdv, and that's our
        //negative grown stalk index.

        //find the difference between the input season and the Silo v3 epoch season
        //using regular - here because we want it to overflow negative
        stem = (int128(season)-int128(s.season.stemStartSeason)).mul(int128(seedsPerBdv));
    }

    // function stemToSeason(uint256 seedsPerBdv, int128 stem)
    //     internal
    //     view
    //     returns (uint32 season)
    // {
    //     // require(stem > 0);
    //     AppStorage storage s = LibAppStorage.diamondStorage();
    //     // uint256 seedsPerBdv = getSeedsPerToken(address(token));

    //     require(seedsPerBdv > 0, "Silo: Token not supported");


    //     int128 diff = stem.div(int128(seedsPerBdv));
    //     //using regular + here becauase we want to "overflow" (which for signed just means add negative)
    //     season = uint256(int128(s.season.stemStartSeason)+diff).toUint32();
    //     // season = seasonAs256.toUint32();
    // }


    //this feels gas inefficient to me, maybe there's a better way? hardcode in values here?
    function getSeedsPerToken(address token) internal pure returns (uint256) {
        if (token == C.beanAddress()) {
            return 2;
        } else if (token == C.unripeBeanAddress()) {
            return 2;
        } else if (token == C.unripeLPAddress()) {
            return 4;
        } else if (token == C.curveMetapoolAddress()) {
            return 4;
        }
        return 0;
    }
}