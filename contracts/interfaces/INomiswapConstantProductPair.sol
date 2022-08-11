// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IERC20.sol";
import "./INomiswapERC20.sol";
import "./INomiswapPair.sol";

interface INomiswapConstantProductPair is INomiswapPair {

    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);
    function devFee() external view returns (uint);

    function initialize(address, address) external;
    function setSwapFee(uint32) external;
    function setDevFee(uint) external;

}
