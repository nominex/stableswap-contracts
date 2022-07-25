// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./IStableSwapERC20.sol";
pragma experimental ABIEncoderV2;

interface IStableSwapPair is IStableSwapERC20 {
    /// @notice Executes a swap from one token to another.
    /// @dev The input tokens must've already been sent to the pool.
//    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external returns (uint256 finalAmountOut);

    function swap(address tokenIn, address recipient) external returns (uint256 amountOut);
    function flashSwap(address tokenIn, address recipient, uint256 amountIn, bytes memory context) external returns (uint256 amountOut);


        /// @notice Mints liquidity tokens.
    /// @return liquidity The amount of liquidity tokens that were minted for the user.
    function mint(address recipient) external returns (uint256 liquidity);

    /// @notice Burns liquidity tokens.
    /// @dev The input LP tokens must've already been sent to the pool.
    /// @return withdrawnAmounts The amount of various output tokens that were sent to the user.
    function burn(address recipient) external returns (TokenAmount[] memory withdrawnAmounts);

    /// @notice Burns liquidity tokens for a single output token.
    /// @dev The input LP tokens must've already been sent to the pool.
    /// @return amountOut The amount of output tokens that were sent to the user.
    function burnSingle(address tokenOut, address recipient) external returns (uint256 amountOut);

    /// @return An array of tokens supported by the pool.
    function getAssets() external view returns (address[] memory);

    /// @notice Simulates a trade and returns the expected output.
    /// @dev The pool does not need to include a trade simulator directly in itself - it can use a library.
    /// @return finalAmountOut The amount of output tokens that will be sent to the user if the trade is executed.
    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 finalAmountOut);

    function setDevFee(uint _devFee) external;
    function setSwapFee(uint _swapFee) external;

    /// @dev This event must be emitted on all swaps.
    event Swap(address indexed recipient, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /// @dev This struct frames output tokens for burns.
    struct TokenAmount {
        address token;
        uint256 amount;
    }
}
