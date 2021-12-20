pragma solidity =0.5.16;

import './interfaces/INomiswapFactory.sol';
import './NomiswapPair.sol';

contract NomiswapFactory is INomiswapFactory {
    using UQ112x112 for uint224;

    uint224 private constant UQ_1 = 2**112;

    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(NomiswapPair).creationCode));

    address public feeTo;
    address public feeToSetter;
    uint224 public invPhiMinusOne = 5 * UQ_1 /*calcInvPhiMinusOne(UQ_1.uqdiv(6))*/;


    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function calcInvPhiMinusOne(uint112 phi) private pure returns (uint224) {
        return UQ_1.uqdiv(phi) - UQ_1;
    }

    function setPhi(uint112 phi) external {
        require(msg.sender == feeToSetter, 'Nomiswap: FORBIDDEN');
        invPhiMinusOne = calcInvPhiMinusOne(phi);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'Nomiswap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Nomiswap: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Nomiswap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(NomiswapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        INomiswapPair(pair).initialize(token0, token1);
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
}
