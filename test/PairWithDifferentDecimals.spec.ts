import chai, { expect } from 'chai'
import { Contract } from '@ethersproject/contracts'
import { createFixtureLoader, MockProvider, solidity } from 'ethereum-waffle'
import { BigNumber, bigNumberify } from 'ethers/utils'

import { expandTo18Decimals, mineBlock } from './shared/utilities'
import { pairWithDifferentDecimalsFixture } from './shared/fixtures'
import { AddressZero } from 'ethers/constants'

const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3);

chai.use(solidity);

const overrides = {
  gasLimit: 9999999
};

describe('NomiswapStablePair with different decimals', () => {
  const provider = new MockProvider({
    ganacheOptions: {
      chain: {
        hardfork: 'istanbul',
      },
      wallet: {
        mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
      },
      miner: {
        blockGasLimit: 9999999
      }
    }
  });
  const [wallet, other] = provider.getWallets();
  const loadFixture = createFixtureLoader( [wallet], provider);

  let factory: Contract;
  let token0: Contract;
  let token1: Contract;
  let pair: Contract;
  let token0Decimals: number;
  let token0Precision: BigNumber;
  let token1Decimals: number;
  let token1Precision: BigNumber;
  beforeEach(async () => {
    const fixture = await loadFixture(pairWithDifferentDecimalsFixture);
    factory = fixture.factory;
    token0 = fixture.token0;
    token1 = fixture.token1;
    pair = fixture.pair;
    token0Decimals = await token0.decimals();
    token0Precision = bigNumberify(10).pow(token0Decimals);
    token1Decimals = await token1.decimals();
    token1Precision = bigNumberify(10).pow(token1Decimals);
  });

  it('mint', async () => {
    const token0Amount = token0Precision.mul(2);
    const token1Amount = token1Precision.mul(2);
    await token0.transfer(pair.address, token0Amount);
    await token1.transfer(pair.address, token1Amount);

    const expectedLiquidity = expandTo18Decimals(4);
    await expect(pair.mint(wallet.address, overrides))
      .to.emit(pair, 'Transfer')
      .withArgs(AddressZero, AddressZero, MINIMUM_LIQUIDITY)
      .to.emit(pair, 'Transfer')
      .withArgs(AddressZero, wallet.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
      .to.emit(pair, 'Sync')
      .withArgs(token0Amount, token1Amount)
      .to.emit(pair, 'Mint')
      .withArgs(wallet.address, token0Amount, token1Amount);

    expect(await pair.totalSupply()).to.eq(expectedLiquidity);
    expect(await pair.balanceOf(wallet.address)).to.eq(expectedLiquidity.sub(MINIMUM_LIQUIDITY));
    expect(await token0.balanceOf(pair.address)).to.eq(token0Amount);
    expect(await token1.balanceOf(pair.address)).to.eq(token1Amount);
    const reserves = await pair.getReserves();
    expect(reserves[0]).to.eq(token0Amount);
    expect(reserves[1]).to.eq(token1Amount)
  });

  async function addLiquidity(token0Amount: BigNumber, token1Amount: BigNumber) {
    await token0.transfer(pair.address, token0Amount);
    await token1.transfer(pair.address, token1Amount);
    await pair.mint(wallet.address, overrides)
  }
  const swapTestCases: BigNumber[][] = [
    [1, 5, 10,     '1002650261175879657'],
    [1, 10, 5,      '992340914158536492'],

    [2, 5, 10,     '2003280109992089343'],
    [2, 10, 5,     '1979181800159165539'],

    [1, 10, 10,     '998409912240233654'],
    [1, 100, 100,   '998940635138455855'],
    [1, 1000, 1000, '998993163776865518']
  ].map(a => a.map(n => bigNumberify(n)));
  swapTestCases.forEach((swapTestCase, i) => {
    it(`getInputPrice:${i}`, async () => {
      expect(await token0.balanceOf(pair.address)).to.eq(0);
      expect(await token1.balanceOf(pair.address)).to.eq(0);
      let [swapAmount, token0Amount, token1Amount, expectedOutputAmount] = swapTestCase;
      token0Amount = token0Amount.mul(token0Precision);
      token1Amount = token1Amount.mul(token1Precision);
      swapAmount = swapAmount.mul(token0Precision);
      expectedOutputAmount = expectedOutputAmount.mul(token1Precision).div(expandTo18Decimals(1));
      await addLiquidity(token0Amount, token1Amount);
      await token0.transfer(pair.address, swapAmount);
      expect(await pair.getAmountOut(token0.address, swapAmount)).to.eq(expectedOutputAmount);
      const amountIn = await pair.getAmountIn(token0.address, expectedOutputAmount);
      expect(await pair.getAmountOut(token0.address, amountIn)).to.eq(expectedOutputAmount);
      const expectedAmountAugment = bigNumberify(2).mul(token1Precision).div(token0Precision)
      await expect(pair.swap(0, expectedOutputAmount.add(expectedAmountAugment), wallet.address, '0x', overrides)).to.be.revertedWith(
        'Nomiswap: D'
      );
      await pair.swap(0, expectedOutputAmount, wallet.address, '0x', overrides)
    })
  });

  const optimisticTestCases: any[][] = [
    ['998999999835854396', 5, 10, 1], // given amountIn, amountOut = floor(amountIn * .999)
    ['998999999835854396', 10, 5, 1],
    ['998999999835854396', 5, 5, 1],
    [1, 5, 5, '1001001001165475390'] // given amountOut, amountIn = ceiling(amountOut / .999)
  ];
  optimisticTestCases.forEach((optimisticTestCase, i) => {
    it(`optimistic:${i}`, async () => {
      let [outputAmount, token0Amount, token1Amount, inputAmount] = optimisticTestCase;
      token0Amount = token0Precision.mul(token0Amount);
      token1Amount = token1Precision.mul(token1Amount);
      if (typeof(inputAmount) === 'string') {
        inputAmount = token0Precision.mul(inputAmount).div(expandTo18Decimals(1)).add(1);
      } else {
        inputAmount = token0Precision.mul(inputAmount);
      }
      if (typeof(outputAmount) === 'string') {
        outputAmount = token0Precision.mul(outputAmount).div(expandTo18Decimals(1));
      } else {
        outputAmount = token0Precision.mul(outputAmount);
      }

      await addLiquidity(token0Amount, token1Amount);
      await token0.transfer(pair.address, inputAmount);
      await expect(pair.swap(outputAmount.add(1), 0, wallet.address, '0x', overrides)).to.be.revertedWith('Nomiswap: D');
      await pair.swap(outputAmount, 0, wallet.address, '0x', overrides)
    })
  });

  it('swap:token0', async () => {
    const token0Amount = token0Precision.mul(5);
    const token1Amount = token1Precision.mul(10);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = token0Precision.mul(1);
    const expectedOutputAmount = (await pair.getAmountOut(token0.address, swapAmount));
    await token0.transfer(pair.address, swapAmount);
    await expect(pair.swap(0, expectedOutputAmount, wallet.address, '0x', overrides))
      .to.emit(token1, 'Transfer')
      .withArgs(pair.address, wallet.address, expectedOutputAmount)
      .to.emit(pair, 'Sync')
      .withArgs(token0Amount.add(swapAmount), token1Amount.sub(expectedOutputAmount))
      .to.emit(pair, 'Swap')
      .withArgs(wallet.address, swapAmount, 0, 0, expectedOutputAmount, wallet.address);

    const reserves = await pair.getReserves();
    expect(reserves[0]).to.eq(token0Amount.add(swapAmount));
    expect(reserves[1]).to.eq(token1Amount.sub(expectedOutputAmount));
    expect(await token0.balanceOf(pair.address)).to.eq(token0Amount.add(swapAmount));
    expect(await token1.balanceOf(pair.address)).to.eq(token1Amount.sub(expectedOutputAmount));
    const totalSupplyToken0 = await token0.totalSupply();
    const totalSupplyToken1 = await token1.totalSupply();
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(token0Amount).sub(swapAmount));
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(token1Amount).add(expectedOutputAmount))
  });

  it('swap:token1', async () => {
    const token0Amount = token0Precision.mul(5);
    const token1Amount = token1Precision.mul(10);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = token1Precision.mul(1);
    const expectedOutputAmount = (await pair.getAmountOut(token1.address, swapAmount));
    await token1.transfer(pair.address, swapAmount);
    await expect(pair.swap(expectedOutputAmount, 0, wallet.address, '0x', overrides))
      .to.emit(token0, 'Transfer')
      .withArgs(pair.address, wallet.address, expectedOutputAmount)
      .to.emit(pair, 'Sync')
      .withArgs(token0Amount.sub(expectedOutputAmount), token1Amount.add(swapAmount))
      .to.emit(pair, 'Swap')
      .withArgs(wallet.address, 0, swapAmount, expectedOutputAmount, 0, wallet.address);

    const reserves = await pair.getReserves();
    expect(reserves[0]).to.eq(token0Amount.sub(expectedOutputAmount));
    expect(reserves[1]).to.eq(token1Amount.add(swapAmount));
    expect(await token0.balanceOf(pair.address)).to.eq(token0Amount.sub(expectedOutputAmount));
    expect(await token1.balanceOf(pair.address)).to.eq(token1Amount.add(swapAmount));
    const totalSupplyToken0 = await token0.totalSupply();
    const totalSupplyToken1 = await token1.totalSupply();
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(token0Amount).add(expectedOutputAmount));
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(token1Amount).sub(swapAmount));
  });

  it('swap:gas', async () => {
    const token0Amount = token0Precision.mul(5);
    const token1Amount = token1Precision.mul(10);
    await addLiquidity(token0Amount, token1Amount);

    // ensure that setting price{0,1}CumulativeLast for the first time doesn't affect our gas math
    await mineBlock(provider, (await provider.getBlock('latest')).timestamp + 1);
    await pair.sync(overrides);

    const swapAmount = token1Precision.mul(1);
    const expectedOutputAmount = token0Precision.mul('453305446940074565').div(expandTo18Decimals(1));
    await token1.transfer(pair.address, swapAmount);
    await mineBlock(provider, (await provider.getBlock('latest')).timestamp + 1);
    const tx = await pair.swap(expectedOutputAmount, 0, wallet.address, '0x', overrides);
    const receipt = await tx.wait();
    expect(receipt.gasUsed).to.eq(82789)
  });

  it('burn', async () => {
    const token0Amount = token0Precision.mul(3);
    const token1Amount = token1Precision.mul(3);
    await addLiquidity(token0Amount, token1Amount);

    const expectedLiquidity = expandTo18Decimals(6);
    await pair.transfer(pair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY));

    const token0Return = token0Amount.mul(expandTo18Decimals(1)).div(token0Precision).sub(500).mul(token0Precision).div(expandTo18Decimals(1));
    const token1Return = token1Amount.mul(expandTo18Decimals(1)).div(token1Precision).sub(500).mul(token1Precision).div(expandTo18Decimals(1));

    await expect(pair.burn(wallet.address, overrides))
      .to.emit(pair, 'Transfer')
      .withArgs(pair.address, AddressZero, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
      .to.emit(token0, 'Transfer')
      .withArgs(pair.address, wallet.address, token0Return)
      .to.emit(token1, 'Transfer')
      .withArgs(pair.address, wallet.address, token1Return)
      .to.emit(pair, 'Sync')
      .withArgs(token0Amount.sub(token0Return), token1Amount.sub(token1Return))
      .to.emit(pair, 'Burn')
      .withArgs(wallet.address, token0Return, token1Return, wallet.address);

    expect(await pair.balanceOf(wallet.address)).to.eq(0);
    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
    expect(await token0.balanceOf(pair.address)).to.eq(token0Amount.sub(token0Return));
    expect(await token1.balanceOf(pair.address)).to.eq(token1Amount.sub(token1Return));
    const totalSupplyToken0 = await token0.totalSupply();
    const totalSupplyToken1 = await token1.totalSupply();
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(token0Amount.sub(token0Return)));
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(token1Amount.sub(token1Return)));
  });

  it('feeTo:off', async () => {
    const token0Amount = token0Precision.mul(1000);
    const token1Amount = token1Precision.mul(1000);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = token1Precision.mul(1);
    const expectedOutputAmount = await pair.getAmountOut(token1.address, swapAmount);
    await token1.transfer(pair.address, swapAmount);
    await pair.swap(expectedOutputAmount, 0, wallet.address, '0x', overrides);

    const expectedLiquidity = expandTo18Decimals(2000);
    await pair.transfer(pair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY));
    await pair.burn(wallet.address, overrides);
    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY)
  });

  it('feeTo:on', async () => {
    await factory.setFeeTo(other.address);

    const token0Amount = token0Precision.mul(1000);
    const token1Amount = token1Precision.mul(1000);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = token1Precision.mul(1);
    const expectedOutputAmount = await pair.getAmountOut(token1.address, swapAmount);
    await token1.transfer(pair.address, swapAmount);
    await pair.swap(expectedOutputAmount, 0, wallet.address, '0x', overrides);

    const expectedLiquidity = expandTo18Decimals(1000);
    await pair.transfer(pair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY));
    await pair.burn(wallet.address, overrides);

    let totalLiquidity = await pair.totalSupply();
    expect(totalLiquidity.sub(expandTo18Decimals(1000)).toNumber()).to.be.lessThan(
      MINIMUM_LIQUIDITY.add('800000000000000').toNumber()
    ).to.be.greaterThan(
      MINIMUM_LIQUIDITY.add('600000000000000').toNumber()
    );
    expect(await pair.balanceOf(other.address)).to.eq('700110442815721');

    // using 1000 here instead of the symbolic MINIMUM_LIQUIDITY because the amounts only happen to be equal...
    // ...because the initial liquidity amounts were equal
    let balance0Expected = bigNumberify(1000).add('499500680625328968030').mul(token0Precision).div(expandTo18Decimals(1));
    let balance0 = await token0.balanceOf(pair.address);
    expect(balance0.sub(balance0Expected).toNumber()).to.be.lessThan(2);
    let balance1Expected = bigNumberify(1000).add('500500175872153612332').mul(token1Precision).div(expandTo18Decimals(1));
    let balance1 = await token1.balanceOf(pair.address);
    expect(balance1.sub(balance1Expected).toNumber()).to.be.lessThan(2)
  });

  it('twoSideTransfer', async () => {
    await factory.setSwapFee(pair.address, 0);

    const token0Amount = token0Precision.mul(1000);
    const token1Amount = token1Precision.mul(1000);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = token0Precision.mul(800);
    const forwardOut = await pair.getAmountOut(token0.address, swapAmount);
    await token0.transfer(pair.address, swapAmount);

    await pair.swap(0, forwardOut, wallet.address, '0x', overrides);

    const reverseOut = await pair.getAmountOut(token1.address, forwardOut);

    expect(swapAmount.sub(reverseOut).toNumber()).to.be.lessThan(10);

    await token1.transfer(pair.address, forwardOut);

    await pair.swap(reverseOut, 0, wallet.address, '0x', overrides);

  });

});
