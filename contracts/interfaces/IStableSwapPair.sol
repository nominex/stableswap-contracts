// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.5.0;

pragma experimental ABIEncoderV2;

interface IStableSwapPair {

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    /*    event Swap(
            address indexed sender,
            uint amount0In,
            uint amount1In,
            uint amount0Out,
            uint amount1Out,
            address indexed to
        );
    */
    /// @dev This event must be emitted on all swaps.
    event Swap(address indexed recipient, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    //    event Sync(uint112 reserve0, uint112 reserve1);
    event Sync(uint256 reserve0, uint256 reserve1);

    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);

    /// @notice Executes a swap from one token to another.
    /// @dev The input tokens must've already been sent to the pool.
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;

    function swap(address tokenIn, address recipient) external returns (uint256 amountOut);
    function flashSwap(address tokenIn, address recipient, uint256 amountIn, bytes memory context) external returns (uint256 amountOut);


    function mint(address to) external returns (uint liquidity);
    function burn(address recipient) external returns (TokenAmount[] memory withdrawnAmounts);

    /// @notice Burns liquidity tokens for a single output token.
    /// @dev The input LP tokens must've already been sent to the pool.
    /// @return amountOut The amount of output tokens that were sent to the user.
    function burnSingle(address tokenOut, address recipient) external returns (uint256 amountOut);

    /// @return An array of tokens supported by the pool.
    function getAssets() external view returns (address[] memory);

    function getAmountIn(address tokenIn, uint256 amountOut) external view returns (uint256 finalAmountIn);
    /// @notice Simulates a trade and returns the expected output.
    /// @dev The pool does not need to include a trade simulator directly in itself - it can use a library.
    /// @return finalAmountOut The amount of output tokens that will be sent to the user if the trade is executed.
    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256 finalAmountOut);

    function setDevFee(uint _devFee) external;
    function setSwapFee(uint _swapFee) external;

    /// @dev This struct frames output tokens for burns.
    struct TokenAmount {
        address token;
        uint256 amount;
    }
}
