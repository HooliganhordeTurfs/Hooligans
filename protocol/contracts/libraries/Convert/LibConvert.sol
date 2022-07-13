/*
 SPDX-License-Identifier: MIT
*/

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import "./LibUnripeConvert.sol";

/**
 * @author Publius
 * @title Lib Convert
 **/
library LibConvert {
    using SafeMath for uint256;
    using LibConvertData for bytes;

    /// @notice Takes in bytes object that has convert input data encoded into it for a particular convert for
    ///         a specified pool and returns the in and out convert amounts and token addresses and bdv
    /// @param convertData Contains convert input parameters for a specified convert
    function convert(bytes memory convertData)
        internal
        returns (
            address tokenOut,
            address tokenIn,
            uint256 outAmount,
            uint256 inAmount
        )
    {
        LibConvertData.ConvertKind kind = convertData.convertKind();

        if (kind == LibConvertData.ConvertKind.BEANS_TO_CURVE_LP) {
            (tokenOut, tokenIn, outAmount, inAmount) = LibCurveConvert
                .convertBeansToLP(convertData);
        } else if (kind == LibConvertData.ConvertKind.CURVE_LP_TO_BEANS) {
            (tokenOut, tokenIn, outAmount, inAmount) = LibCurveConvert
                .convertLPToBeans(convertData);
        } else if (kind == LibConvertData.ConvertKind.UNRIPE_BEANS_TO_UNRIPE_LP) {
            (tokenOut, tokenIn, outAmount, inAmount) = LibUnripeConvert
                .convertBeansToLP(convertData);
        } else if (kind == LibConvertData.ConvertKind.UNRIPE_LP_TO_UNRIPE_BEANS) {
            (tokenOut, tokenIn, outAmount, inAmount) = LibUnripeConvert
                .convertLPToBeans(convertData);
        } else {
            revert("Convert: Invalid payload");
        }
    }

    function getMaxAmountIn(address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 amountIn)
    {
        if (tokenIn == C.curveMetapoolAddress() && tokenOut == C.beanAddress())
            return LibCurveConvert.lpToPeg(C.curveMetapoolAddress());
        if (tokenIn == C.beanAddress() && tokenOut == C.curveMetapoolAddress())
            return LibCurveConvert.beansToPeg(C.curveMetapoolAddress());
        if (tokenIn == C.unripeLPAddress() && tokenOut == C.unripeBeanAddress())
            return LibUnripeConvert.lpToPeg();
        if (tokenIn == C.unripeBeanAddress() && tokenOut == C.unripeLPAddress())
            return LibUnripeConvert.beansToPeg();
        require(false, "Convert: Tokens not supported");
    }

    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn)
        internal 
        view
        returns (uint256 amountOut)
    {
        if (tokenIn == C.curveMetapoolAddress() && tokenOut == C.beanAddress())
            return LibCurveConvert.getBeanAmountOut(C.curveMetapoolAddress(), amountIn);
        if (tokenIn == C.beanAddress() && tokenOut == C.curveMetapoolAddress())
            return LibCurveConvert.getLPAmountOut(C.curveMetapoolAddress(), amountIn);
        if (tokenIn == C.unripeLPAddress() && tokenOut == C.unripeBeanAddress())
            return LibUnripeConvert.getBeanAmountOut(amountIn);
        if (tokenIn == C.beanAddress() && tokenOut == C.unripeLPAddress())
            return LibUnripeConvert.getLPAmountOut(amountIn);
        require(false, "Convert: Tokens not supported");
    }
}