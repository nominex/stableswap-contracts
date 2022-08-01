// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import "./INomiswapERC20.sol";
import "./INomiswapPair.sol";
pragma experimental ABIEncoderV2;

interface INomiswapStablePair is INomiswapPair {

    function devFee() external view returns (uint);

//    function burnSingle(address tokenOut, address recipient) external returns (uint256 amountOut);

    function getA() external view returns (uint256);

    function setSwapFee(uint32) external;
    function setDevFee(uint) external;

    function rampA(uint256 _futureA, uint256 _futureTime) external;
    function stopRampA() external;

}
