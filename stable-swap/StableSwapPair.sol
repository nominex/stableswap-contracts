// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "./interfaces/IERC20.sol";

import "./interfaces/IStableSwapPair.sol";
import "./interfaces/INomiswapCallee.sol";
import "./interfaces/INomiswapFactory.sol";
import "./StableSwapERC20.sol";
import "./libraries/MathUtils.sol";


/// @notice StableSwap exchange pool template for swapping between an ERC-20 token pair.
contract StableSwapPair is IStableSwapPair, StableSwapERC20 {
    using MathUtils for uint256;

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient, uint256 liquidity);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient, uint256 liquidity);
    event Sync(uint256 reserve0, uint256 reserve1);

    event RampA(uint256 oldA, uint256 newA, uint256 initialTime, uint256 futureTime);
    event StopRampA(uint256 A, uint256 t);

    uint256 internal constant MINIMUM_LIQUIDITY = 10**3;

    /// @dev Constant value used as max loop limit.
    uint256 private constant MAX_LOOP_LIMIT = 256;
    uint256 internal constant MAX_FEE = 10000; // @dev 100%.

    uint256 internal constant MAX_A = 10 ** 6;
    uint256 internal constant MAX_A_CHANGE = 10;
    uint256 internal constant MIN_RAMP_TIME = 86400;


    address public immutable token0;
    address public immutable token1;

    address public factory;
    uint256 public swapFee;

    uint256 internal constant A_PRECISION = 100;

    /// @dev Multipliers for each pooled token's precision to get to POOL_PRECISION_DECIMALS.
    /// For example, TBTC has 18 decimals, so the multiplier should be 1. WBTC
    /// has 8, so the multiplier should be 10 ** 18 / 10 ** 8 => 10 ** 10.
    uint256 public immutable token0PrecisionMultiplier;
    uint256 public immutable token1PrecisionMultiplier;

    uint256 public devFee = MAX_FEE * 70 / 100;

    uint128 internal reserve0;
    uint128 internal reserve1;
    uint256 internal dLast;

    uint256 initialA;
    uint256 futureA;
    uint256 initialATime;
    uint256 futureATime;


    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Nomiswap: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor(address _token0, address _token1, uint256 _swapFee, uint256 a) StableSwapERC20() {

        factory = msg.sender;

        // @dev Factory ensures that the tokens are sorted.
        require(_token0 != address(0), "ZERO_ADDRESS");
        require(_token0 != _token1, "IDENTICAL_ADDRESSES");
        require(_swapFee <= MAX_FEE, "INVALID_SWAP_FEE");
        require(a != 0, "ZERO_A");

        token0 = _token0;
        token1 = _token1;
        swapFee = _swapFee;

        initialA = a;
        futureA = a;
        initialATime = block.timestamp;
        futureATime = block.timestamp;

        token0PrecisionMultiplier = uint256(10)**(18 - IERC20(_token0).decimals());
        token1PrecisionMultiplier = uint256(10)**(18 - IERC20(_token1).decimals());
    }

    function setDevFee(uint _devFee) external override {
        require(_devFee != 0, "NomiswapPair: dev fee 0");
        require(msg.sender == factory, 'NomiswapPair: FORBIDDEN');
        require(_devFee <= MAX_FEE, 'NomiswapPair: FORBIDDEN_FEE');
        devFee = _devFee;
    }

    function setSwapFee(uint _swapFee) external override {
        require(_swapFee != 0, "NomiswapPair: dev fee 0");
        require(msg.sender == factory, 'NomiswapPair: FORBIDDEN');
        require(_swapFee <= MAX_FEE, 'NomiswapPair: FORBIDDEN_FEE');
        swapFee = _swapFee;
    }

    function getA() public view returns (uint256) {
        uint256 t1  = futureATime;
        uint256 A1  = futureA;

        if (block.timestamp < t1) {
            uint256 A0 = initialA;
            uint256 t0 = initialATime;
            // Expressions in uint256 cannot have negative numbers, thus "if"
            if (A1 > A0) {
                return A0 + (A1 - A0) * (block.timestamp - t0) / (t1 - t0);
            } else {
                return A0 - (A0 - A1) * (block.timestamp - t0) / (t1 - t0);
            }
        } else {
            // when t1 == 0 or block.timestamp >= t1
            return A1;
        }
    }

    function rampA(uint256 _futureA, uint256 _futureTime) external {

        require(msg.sender == factory, 'NomiswapPair: FORBIDDEN');
        require(block.timestamp >= initialATime + MIN_RAMP_TIME, 'NomiswapPair: INVALID_TIME');
        require(_futureTime >= block.timestamp + MIN_RAMP_TIME, 'NomiswapPair: INVALID_FUTURE_TIME');

        uint256 _initialA = getA();
        uint256 _futureAP = _futureA * A_PRECISION;

        require(_futureA > 0 && _futureA < MAX_A);

        if (_futureAP < _initialA) {
            require(_futureAP * MAX_A_CHANGE >= _initialA);
        } else {
            require(_futureAP <= _initialA * MAX_A_CHANGE);
        }

        initialA = _initialA;
        futureA = _futureAP;
        initialATime = block.timestamp;
        futureATime = _futureTime;

        emit RampA(_initialA, _futureAP, block.timestamp, _futureTime);
    }

    function stopRampA() external {

        require(msg.sender == factory, 'NomiswapPair: FORBIDDEN');

        uint256 currentA = getA();
        initialA = currentA;
        futureA = currentA;
        initialATime = block.timestamp;
        futureATime = block.timestamp;

        emit StopRampA(currentA, block.timestamp);
    }


    /// @dev Mints LP tokens - should be called via the router after transferring tokens.
    /// The router must ensure that sufficient LP tokens are minted by using the return value.
    function mint(address recipient) public override lock returns (uint256 liquidity) {
        (uint256 _reserve0, uint256 _reserve1) = _getReserves();
        (uint256 balance0, uint256 balance1) = _balance();

        uint256 newLiq = _computeLiquidity(balance0, balance1);
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        (uint256 fee0, uint256 fee1) = _nonOptimalMintFee(amount0, amount1, _reserve0, _reserve1);
        _reserve0 += fee0;
        _reserve1 += fee1;

        (uint256 _totalSupply, uint256 oldLiq) = _mintFee(_reserve0, _reserve1);

        if (_totalSupply == 0) {
            require(amount0 > 0 && amount1 > 0, "INVALID_AMOUNTS");
            liquidity = newLiq - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = ((newLiq - oldLiq) * _totalSupply) / oldLiq;
        }
        require(liquidity != 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(recipient, liquidity);
        _updateReserves();

        dLast = newLiq;
        uint256 liquidityForEvent = liquidity;
        emit Mint(msg.sender, amount0, amount1, recipient, liquidityForEvent);
    }

    /// @dev Burns LP tokens sent to this contract. The router must ensure that the user gets sufficient output tokens.
    function burn(address recipient) public override lock returns (IStableSwapPair.TokenAmount[] memory withdrawnAmounts) {

        (uint256 balance0, uint256 balance1) = _balance();
        uint256 liquidity = balanceOf[address(this)];

        (uint256 _totalSupply, ) = _mintFee(balance0, balance1);

        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);
        _transfer(token0, amount0, recipient);
        _transfer(token1, amount1, recipient);

        _updateReserves();

        withdrawnAmounts = new TokenAmount[](2);
        withdrawnAmounts[0] = TokenAmount({token: token0, amount: amount0});
        withdrawnAmounts[1] = TokenAmount({token: token1, amount: amount1});

        dLast = _computeLiquidity(balance0 - amount0, balance1 - amount1);

        emit Burn(msg.sender, amount0, amount1, recipient, liquidity);
    }

    /// @dev Burns LP tokens sent to this contract and swaps one of the output tokens for another
    /// - i.e., the user gets a single token out by burning LP tokens.
    function burnSingle(address tokenOut, address recipient) public override lock returns (uint256 amountOut) {
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 liquidity = balanceOf[address(this)];

        (uint256 _totalSupply, ) = _mintFee(balance0, balance1);

        uint256 amount0 = (liquidity * balance0) / _totalSupply;
        uint256 amount1 = (liquidity * balance1) / _totalSupply;

        _burn(address(this), liquidity);
        dLast = _computeLiquidity(balance0 - amount0, balance1 - amount1);

        // Swap tokens
        if (tokenOut == token1) {
            // @dev Swap `token0` for `token1`.
            // @dev Calculate `amountOut` as if the user first withdrew balanced liquidity and then swapped `token0` for `token1`.
            amount1 += _getAmountOut(amount0, balance0 - amount0, balance1 - amount1, true);
            _transfer(token1, amount1, recipient);
            amountOut = amount1;
            amount0 = 0;
        } else {
            // @dev Swap `token1` for `token0`.
            require(tokenOut == token0, "INVALID_OUTPUT_TOKEN");
            amount0 += _getAmountOut(amount1, balance0 - amount0, balance1 - amount1, false);
            _transfer(token0, amount0, recipient);
            amountOut = amount0;
            amount1 = 0;
        }
        _updateReserves();
        emit Burn(msg.sender, amount0, amount1, recipient, liquidity);
    }

    /// @dev Swaps one token for another. The router must prefund this contract and ensure there isn't too much slippage.
    function swap(address tokenIn, address recipient) public override lock returns (uint256 amountOut) {
        (uint256 _reserve0, uint256 _reserve1, uint256 balance0, uint256 balance1) = _getReservesAndBalances();
        uint256 amountIn;
        address tokenOut;

        if (tokenIn == token0) {
            tokenOut = token1;
            unchecked {
                amountIn = balance0 - _reserve0;
            }
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1, true);
        } else {
            require(tokenIn == token1, "INVALID_INPUT_TOKEN");
            tokenOut = token0;
            unchecked {
                amountIn = balance1 - _reserve1;
            }
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1, false);
        }
        _transfer(tokenOut, amountOut, recipient);
        _updateReserves();
        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @dev Swaps one token for another with payload. The router must support swap callbacks and ensure there isn't too much slippage.
    function flashSwap(address tokenIn, address recipient, uint256 amountIn, bytes memory context) public override lock returns (uint256 amountOut) {

        (uint256 _reserve0, uint256 _reserve1) = _getReserves();
        address tokenOut;

        if (tokenIn == token0) {
            tokenOut = token1;
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1, true);
            _processSwap(token1, recipient, amountOut, context);
            uint256 balance0 = IERC20(token0).balanceOf(address(this));
            require(balance0 - _reserve0 >= amountIn, "INSUFFICIENT_AMOUNT_IN");
        } else {
            require(tokenIn == token1, "INVALID_INPUT_TOKEN");
            tokenOut = token0;
            amountOut = _getAmountOut(amountIn, _reserve0, _reserve1, false);
            _processSwap(token0, recipient, amountOut, context);
            uint256 balance1 = IERC20(token1).balanceOf(address(this));
            require(balance1 - _reserve1 >= amountIn, "INSUFFICIENT_AMOUNT_IN");
        }
        _updateReserves();
        emit Swap(recipient, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @dev Updates `barFee` for Trident protocol.
    function updateBarFee() public {
//        barFee = masterDeployer.barFee();
    }

    function _processSwap(
        address tokenOut,
        address to,
        uint256 amountOut,
        bytes memory data
    ) internal {
        _transfer(tokenOut, amountOut, to);
        uint256 amount0;
        uint256 amount1;
        if (tokenOut == token0) {
            amount0 = amountOut;
        } else {
            amount1 = amountOut;
        }
        if (data.length != 0) INomiswapCallee(msg.sender).nomiswapCall(
            address(this),
            amount0,
            amount1,
            data
        );
    }

    function _getReserves() internal view returns (uint256 _reserve0, uint256 _reserve1) {
        (_reserve0, _reserve1) = (reserve0, reserve1);
    }

    function _getReservesAndBalances()
        internal
        view
        returns (
            uint256 _reserve0,
            uint256 _reserve1,
            uint256 balance0,
            uint256 balance1
        )
    {
        (_reserve0, _reserve1) = (reserve0, reserve1);
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
    }

    function _updateReserves() internal {
        (uint256 _reserve0, uint256 _reserve1) = _balance();
        require(_reserve0 <= type(uint128).max && _reserve1 <= type(uint128).max, "OVERFLOW");
        reserve0 = uint128(_reserve0);
        reserve1 = uint128(_reserve1);
        emit Sync(_reserve0, _reserve1);
    }

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
    }

    function _getAmountOut(
        uint256 amountIn,
        uint256 _reserve0,
        uint256 _reserve1,
        bool token0In
    ) internal view returns (uint256 dy) {
        unchecked {
            uint256 adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
            uint256 adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
            uint256 feeDeductedAmountIn = amountIn - (amountIn * swapFee) / MAX_FEE;
            uint256 d = _computeLiquidityFromAdjustedBalances(adjustedReserve0, adjustedReserve1);

            if (token0In) {
                uint256 x = adjustedReserve0 + (feeDeductedAmountIn * token0PrecisionMultiplier);
                uint256 y = _getY(x, d);
                dy = adjustedReserve1 - y - 1;
                dy /= token1PrecisionMultiplier;
            } else {
                uint256 x = adjustedReserve1 + (feeDeductedAmountIn * token1PrecisionMultiplier);
                uint256 y = _getY(x, d);
                dy = adjustedReserve0 - y - 1;
                dy /= token0PrecisionMultiplier;
            }
        }
    }

    function _transfer(
        address token,
        uint256 amount,
        address to
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Nomiswap: TRANSFER_FAILED');
    }

    /// @notice Get D, the StableSwap invariant, based on a set of balances and a particular A.
    /// See the StableSwap paper for details.
    /// @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L319.
    /// @return liquidity The invariant, at the precision of the pool.
    function _computeLiquidity(uint256 _reserve0, uint256 _reserve1) internal view returns (uint256 liquidity) {
        unchecked {
            uint256 adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
            uint256 adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
            liquidity = _computeLiquidityFromAdjustedBalances(adjustedReserve0, adjustedReserve1);
        }
    }

    function _computeLiquidityFromAdjustedBalances(uint256 xp0, uint256 xp1) internal view returns (uint256 computed) {
        uint256 s = xp0 + xp1;

        uint256 N_A = getA() * 2;
        if (s == 0) {
            computed = 0;
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

    /// @notice Calculate the new balances of the tokens given the indexes of the token
    /// that is swapped from (FROM) and the token that is swapped to (TO).
    /// This function is used as a helper function to calculate how much TO token
    /// the user should receive on swap.
    /// @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L432.
    /// @param x The new total amount of FROM token.
    /// @return y The amount of TO token that should remain in the pool.
    function _getY(uint256 x, uint256 D) internal view returns (uint256 y) {
        uint256 N_A = getA() * 2;
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

    function _mintFee(uint256 _reserve0, uint256 _reserve1) internal returns (uint256 _totalSupply, uint256 d) {
        address feeTo = INomiswapFactory(factory).feeTo();
        _totalSupply = totalSupply;
        uint256 _dLast = dLast;
        if (_dLast != 0) {
            d = _computeLiquidity(_reserve0, _reserve1);
            if (d > _dLast) {
                // @dev `barFee` % of increase in liquidity.
                uint256 _devFee = devFee;
                uint256 numerator = _totalSupply * (d - _dLast) * _devFee;
                uint256 denominator = (MAX_FEE - _devFee) * d + _devFee * _dLast;
                uint256 liquidity = numerator / denominator;

                if (liquidity != 0) {
                    _mint(feeTo, liquidity);
                    _totalSupply += liquidity;
                }
            }
        }
    }

    /// @dev This fee is charged to cover for `swapFee` when users add unbalanced liquidity.
    function _nonOptimalMintFee(
        uint256 _amount0,
        uint256 _amount1,
        uint256 _reserve0,
        uint256 _reserve1
    ) internal view returns (uint256 token0Fee, uint256 token1Fee) {
        if (_reserve0 == 0 || _reserve1 == 0) return (0, 0);
        uint256 amount1Optimal = (_amount0 * _reserve1) / _reserve0;

        if (amount1Optimal <= _amount1) {
            token1Fee = (swapFee * (_amount1 - amount1Optimal)) / (2 * MAX_FEE);
        } else {
            uint256 amount0Optimal = (_amount1 * _reserve0) / _reserve1;
            token0Fee = (swapFee * (_amount0 - amount0Optimal)) / (2 * MAX_FEE);
        }
    }

    function getAssets() public view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    function getAmountIn(address tokenIn, uint256 amountOut) public view override returns (uint256 finalAmountIn) {
        (uint256 _reserve0, uint256 _reserve1) = _getReserves();


        unchecked {
            uint256 adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
            uint256 adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;

            uint256 d = _computeLiquidityFromAdjustedBalances(adjustedReserve0, adjustedReserve1);

            if (tokenIn == token0) {
                uint256 x = adjustedReserve1 - amountOut;
                uint256 y = _getY(x, d);
                uint256 dy = y + 1 - adjustedReserve0;
                dy /= token0PrecisionMultiplier;
                finalAmountIn = dy * MAX_FEE / (MAX_FEE - swapFee);
            } else {
                require(tokenIn == token1, "INVALID_INPUT_TOKEN");
                uint256 x = adjustedReserve0 - amountOut;
                uint256 y = _getY(x, d);
                uint256 dy = y + 1 - adjustedReserve1;
                dy /= token1PrecisionMultiplier;
                finalAmountIn = dy * MAX_FEE / (MAX_FEE - swapFee);
            }
        }
    }

    function getAmountOut(address tokenIn, uint256 amountIn) public view override returns (uint256 finalAmountOut) {
        (uint256 _reserve0, uint256 _reserve1) = _getReserves();

        if (tokenIn == token0) {
            finalAmountOut = _getAmountOut(amountIn, _reserve0, _reserve1, true);
        } else {
            require(tokenIn == token1, "INVALID_INPUT_TOKEN");
            finalAmountOut = _getAmountOut(amountIn, _reserve0, _reserve1, false);
        }
    }

    function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1) {
        (_reserve0, _reserve1) = _getReserves();
    }

    function getVirtualPrice() public view returns (uint256 virtualPrice) {
        (uint256 _reserve0, uint256 _reserve1) = _getReserves();
        uint256 d = _computeLiquidity(_reserve0, _reserve1);
        virtualPrice = (d * (uint256(10)**decimals)) / totalSupply;
    }

}
