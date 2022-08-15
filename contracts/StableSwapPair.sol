// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.15;

import "./interfaces/INomiswapStablePair.sol";
import "./interfaces/INomiswapCallee.sol";
import "./interfaces/INomiswapFactory.sol";
import "./StableSwapERC20.sol";
import "./libraries/MathUtils.sol";
import "./libraries/UQ112x112.sol";
import "./libraries/Math.sol";
import "./util/FactoryGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract StableSwapPair is INomiswapStablePair, StableSwapERC20, ReentrancyGuard, FactoryGuard {
    using MathUtils for uint256;

    uint224 constant Q112 = 2**112;

    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;

    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public dLast; // invariant
    uint256 internal constant MAX_FEE = 10000; // @dev 100%.
    uint32 public swapFee = 10; // uses 0.1% default
    uint public devFee = uint(Q112*(10-7))/uint(7); // 70% (1/0.7-1)

    uint32 internal constant A_PRECISION = 100;

    uint256 private constant MAX_LOOP_LIMIT = 256;

    uint256 internal constant MAX_A = 10 ** 6;
    uint256 internal constant MAX_A_CHANGE = 10;
    uint256 internal constant MIN_RAMP_TIME = 86400;


    uint128 public token0PrecisionMultiplier; // uses single storage slot
    uint128 public token1PrecisionMultiplier; // uses single storage slot

    uint32 initialA = 85 * A_PRECISION; // uses single storage slot
    uint32 futureA = 85 * A_PRECISION; // uses single storage slot
    uint40 initialATime; // uses single storage slot
    uint40 futureATime; // uses single storage slot

    constructor() FactoryGuard(msg.sender) {
        futureATime = uint40(block.timestamp);
    }

    function initialize(address _token0, address _token1) external onlyFactory {
        token0 = _token0;
        token1 = _token1;
        uint8 decimals0 = IERC20Metadata(_token0).decimals();
        require(decimals0 <= 18, 'NomiswapPair: unsupported token');
        token0PrecisionMultiplier = uint128(10)**(18 - decimals0);
        uint8 decimals1 = IERC20Metadata(_token1).decimals();
        require(decimals1 <= 18, 'NomiswapPair: unsupported token');
        token1PrecisionMultiplier = uint128(10)**(18 - decimals1);
    }

    function setSwapFee(uint32 _swapFee) override external onlyFactory {
        require(_swapFee <= MAX_FEE, 'NomiswapPair: FORBIDDEN_FEE');
        swapFee = _swapFee;
    }

    function setDevFee(uint _devFee) override external onlyFactory {
        require(_devFee != 0, "NomiswapPair: dev fee 0");
        devFee = _devFee;
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) override external nonReentrant returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        uint A = getA();
        uint dBalance = _computeLiquidity(balance0, balance1, A);
        uint amount0 = balance0 - _reserve0;
        uint amount1 = balance1 - _reserve1;
        if (_totalSupply == 0) {
            liquidity = _computeLiquidity(amount0, amount1, A) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            uint256 dReserve = _computeLiquidity(reserve0, reserve1, A);
            liquidity = (dBalance - dReserve) * _totalSupply/dReserve;
        }
        require(liquidity > 0, 'Nomiswap: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1);
        if (feeOn) dLast = dBalance; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) override external nonReentrant returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity * balance0 / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * balance1 / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'Nomiswap: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        SafeERC20.safeTransfer(IERC20(_token0), to, amount0);
        SafeERC20.safeTransfer(IERC20(_token1), to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1);
        if (feeOn) dLast = _computeLiquidity(reserve0, reserve1, getA()); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) override external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, 'Nomiswap: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint _reserve0, uint _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'Nomiswap: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, 'Nomiswap: INVALID_TO');
            if (amount0Out > 0) SafeERC20.safeTransfer(IERC20(_token0), to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) SafeERC20.safeTransfer(IERC20(_token1), to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) INomiswapCallee(to).nomiswapCall(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'Nomiswap: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors

            uint256 A = getA();
            uint _swapFee = swapFee;

            uint balance0Adjusted = (balance0 * MAX_FEE - amount0In * _swapFee) * token0PrecisionMultiplier / MAX_FEE;
            uint balance1Adjusted = (balance1 * MAX_FEE - amount1In * _swapFee) * token1PrecisionMultiplier / MAX_FEE;
            uint256 dBalance = _computeLiquidityFromAdjustedBalances(balance0Adjusted, balance1Adjusted, A);

            uint256 adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
            uint256 adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
            uint256 dReserves = _computeLiquidityFromAdjustedBalances(adjustedReserve0, adjustedReserve1, A);

            require(dBalance >= dReserves, 'Nomiswap: D');
        }

        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) override external nonReentrant {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        SafeERC20.safeTransfer(IERC20(_token0), to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        SafeERC20.safeTransfer(IERC20(_token1), to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    // force reserves to match balances
    function sync() override external nonReentrant {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }

    function rampA(uint32 _futureA, uint40 _futureTime) override external nonReentrant onlyFactory {

        require(block.timestamp >= initialATime + MIN_RAMP_TIME, 'NomiswapPair: INVALID_TIME');
        require(_futureTime >= block.timestamp + MIN_RAMP_TIME, 'NomiswapPair: INVALID_FUTURE_TIME');

        uint32 _initialA = getA();
        uint32 _futureAP = _futureA * A_PRECISION;

        require(_futureA > 0 && _futureA < MAX_A);

        if (_futureAP < _initialA) {
            require(_futureAP * MAX_A_CHANGE >= _initialA);
        } else {
            require(_futureAP <= _initialA * MAX_A_CHANGE);
        }

        initialA = _initialA;
        futureA = _futureAP;
        initialATime = uint40(block.timestamp);
        futureATime = _futureTime;

        emit RampA(_initialA, _futureAP, block.timestamp, _futureTime);
    }

    function stopRampA() override external nonReentrant onlyFactory {
        uint32 currentA = getA();
        initialA = currentA;
        futureA = currentA;
        initialATime = uint40(block.timestamp);
        futureATime = uint40(block.timestamp);

        emit StopRampA(currentA, block.timestamp);
    }

    function getAmountIn(address tokenIn, uint256 amountOut) external view override returns (uint256 finalAmountIn) {
        (uint256 _reserve0, uint256 _reserve1, ) = getReserves();

        unchecked {
            uint256 adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
            uint256 adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
            uint256 A = getA();
            uint256 d = _computeLiquidityFromAdjustedBalances(adjustedReserve0, adjustedReserve1, A);

            if (tokenIn == token0) {
                uint256 x = adjustedReserve1 - amountOut * token1PrecisionMultiplier;
                uint256 y = _getY(x, d, A);
                uint256 dy = (y - adjustedReserve0) / token0PrecisionMultiplier + 2;
                finalAmountIn = dy * MAX_FEE / (MAX_FEE - swapFee);
            } else {
                require(tokenIn == token1, "INVALID_INPUT_TOKEN");
                uint256 x = adjustedReserve0 - amountOut * token0PrecisionMultiplier;
                uint256 y = _getY(x, d, A);
                uint256 dy = (y - adjustedReserve1) / token1PrecisionMultiplier + 2;
                finalAmountIn = dy * MAX_FEE / (MAX_FEE - swapFee);
            }
        }
    }

    function getAmountOut(address tokenIn, uint256 amountIn) external view override returns (uint256 finalAmountOut) {
        (uint256 _reserve0, uint256 _reserve1, ) = getReserves();


        unchecked {
            uint256 feeDeductedAmountIn = amountIn - (amountIn * swapFee) / MAX_FEE;
            uint256 adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
            uint256 adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
            uint256 A = getA();
            uint256 d = _computeLiquidityFromAdjustedBalances(adjustedReserve0, adjustedReserve1, A);

            if (tokenIn == token0) {
                uint256 x = adjustedReserve0 + feeDeductedAmountIn * token0PrecisionMultiplier;
                uint256 y = _getY(x, d, A);
                finalAmountOut = (adjustedReserve1 - y) / token1PrecisionMultiplier - 2;
            } else {
                require(tokenIn == token1, "INVALID_INPUT_TOKEN");
                uint256 x = adjustedReserve1 + feeDeductedAmountIn * token1PrecisionMultiplier;
                uint256 y = _getY(x, d, A);
                finalAmountOut = (adjustedReserve0 - y) / token0PrecisionMultiplier - 2;
            }
        }
    }

    function getReserves() override public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function factory() override public view returns (address) {
        return _factory;
    }

    function getA() override public view returns (uint32) {
        uint40 t1  = futureATime;
        uint32 A1  = futureA;

        if (block.timestamp < t1) {
            uint32 A0 = initialA;
            uint40 t0 = initialATime;
            // Expressions in uint32 cannot have negative numbers, thus "if"
            if (A1 > A0) {
                return uint32(A0 + (block.timestamp - t0) * (A1 - A0) / (t1 - t0));
            } else {
                return uint32(A0 - (block.timestamp - t0) * (A0 - A1) / (t1 - t0));
            }
        } else {
            // when t1 == 0 or block.timestamp >= t1
            return A1;
        }
    }

    function _computeLiquidity(uint256 _reserve0, uint256 _reserve1, uint256 A) private view returns (uint256 liquidity) {
        unchecked {
            uint256 adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
            uint256 adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
            liquidity = _computeLiquidityFromAdjustedBalances(adjustedReserve0, adjustedReserve1, A);
        }
    }

    function _update(uint balance0, uint balance1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'Nomiswap: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = INomiswapFactory(factory()).feeTo();
        feeOn = feeTo != address(0);
        uint _dLast = dLast; // gas savings
        if (feeOn) {
            if (_dLast != 0) {
                uint d = _computeLiquidity(_reserve0, _reserve1, getA());
                if (d > dLast) {
                    uint numerator = totalSupply * (d - dLast);
                    uint denominator = (d * devFee/Q112) + dLast;
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_dLast != 0) {
            dLast = 0;
        }
    }

    function _computeLiquidityFromAdjustedBalances(uint256 xp0, uint256 xp1, uint256 A) private pure returns (uint256 computed) {
        uint256 s = xp0 + xp1;

        uint256 N_A = A * 4;
        if (s == 0) {
            return 0;
        }
        uint256 prevD;
        uint256 D = s;
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            uint256 dP = (((D * D) / xp0) * D) / xp1 / 4;
            prevD = D;
            D = (((N_A * s) / A_PRECISION + 2 * dP) * D) / ((N_A / A_PRECISION - 1) * D + 3 * dP);
            if (D.within1(prevD)) {
                break;
            }
        }
        computed = D;
    }

    function _getY(uint256 x, uint256 D, uint256 A) private pure returns (uint256 y) {
        uint256 N_A = A * 4;
        uint256 c = (D * D) / (x * 2);
        c = (c * D) / ((N_A * 2) / A_PRECISION);
        uint256 b = x + ((D * A_PRECISION) / N_A);
        uint256 yPrev;
        y = D;
        // @dev Iterative approximation.
        for (uint256 i = 0; i < MAX_LOOP_LIMIT; i++) {
            yPrev = y;
            y = (y * y + c) / (y * 2 + b - D);
            if (y.within1(yPrev)) {
                break;
            }
        }
    }

}
