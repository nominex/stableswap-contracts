// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./INomiswapERC20.sol";
import "./INomiswapPair.sol";
pragma experimental ABIEncoderV2;

interface INomiswapStablePair is INomiswapPair {

    event RampA(uint256 oldA, uint256 newA, uint256 initialTime, uint256 futureTime);
    event StopRampA(uint256 A, uint256 t);

    function devFee() external view returns (uint);

//    function burnSingle(address tokenOut, address recipient) external returns (uint256 amountOut);

    function getA() external view returns (uint256);

    function setSwapFee(uint32) external;
    function setDevFee(uint) external;

    function rampA(uint256 _futureA, uint256 _futureTime) external;
    function stopRampA() external;

    function getAmountIn(address tokenIn, uint256 amountOut) external view returns (uint256);
    function getAmountOut(address tokenIn, uint256 amountIn) external view returns (uint256);

}
