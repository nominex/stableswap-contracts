// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import './StableSwapPair.sol';
import './interfaces/INomiswapFactory.sol';

contract StableSwapFactory is INomiswapFactory, Ownable {

    address public feeTo;
    address public feeToSetter;
    bytes32 public INIT_CODE_HASH = keccak256(abi.encodePacked(type(StableSwapPair).creationCode));

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    constructor(address _feeToSetter) Ownable(msg.sender) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external onlyOwner returns (address pair) {
        require(tokenA != tokenB, 'Nomiswap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Nomiswap: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Nomiswap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(StableSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(pair != address(0), "Nomiswap: PAIR_NOT_CREATED");
        StableSwapPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

    function setDevFee(address _pair, uint256 _devFee) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        require(_devFee > 0, 'Nomiswap: FORBIDDEN_FEE');
        INomiswapStablePair(_pair).setDevFee(_devFee);
    }

    function setSwapFee(address _pair, uint32 _swapFee) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        INomiswapStablePair(_pair).setSwapFee(_swapFee);
    }

    function rampA(address _pair, uint256 _futureA, uint256 _futureTime) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        StableSwapPair(_pair).rampA(_futureA, _futureTime);
    }

    function stopRampA(address _pair) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        StableSwapPair(_pair).stopRampA();
    }

}
