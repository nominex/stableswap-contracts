import chai, { expect } from 'chai'
import { Contract } from '@ethersproject/contracts'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'
import { BigNumber, bigNumberify } from 'ethers/utils'

import { expandTo18Decimals, mineBlock, encodePrice } from './shared/utilities'
import { pairFixture } from './shared/fixtures'
import { AddressZero } from 'ethers/constants'

const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3);

chai.use(solidity);

const overrides = {
  gasLimit: 9999999
};

describe('NomiswapStablePair', () => {
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
  beforeEach(async () => {
    const fixture = await loadFixture(pairFixture);
    factory = fixture.factory;
    token0 = fixture.token0;
    token1 = fixture.token1;
    pair = fixture.pair
  });

  it('mint', async () => {
    const token0Amount = expandTo18Decimals(2);
    const token1Amount = expandTo18Decimals(2);
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
    [1, 5, 10,     '1002651263549619893'],
    [1, 10, 5,      '992341905199939338'],

    [2, 5, 10,     '2003281110449738491'],
    [2, 10, 5,     '1979182783270639837'],

    [1, 10, 10,     '998410910885544801'],
    [1, 100, 100,   '998941634857474575'],
    [1, 1000, 1000, '998994163601037707'],
    ['3073608539079599913', 10, 10, '3064468431129174971']
  ].map(a => a.map(n => (typeof n === 'string' ? bigNumberify(n) : expandTo18Decimals(n))));
  swapTestCases.forEach((swapTestCase, i) => {
    it(`getInputPrice:${i}`, async () => {
      expect(await token0.balanceOf(pair.address)).to.eq(0);
      expect(await token1.balanceOf(pair.address)).to.eq(0);
      const [swapAmount, token0Amount, token1Amount, expectedOutputAmount] = swapTestCase;
      await addLiquidity(token0Amount, token1Amount);
      await token0.transfer(pair.address, swapAmount);
      expect(await pair.getAmountOut(token0.address, swapAmount)).to.eq(expectedOutputAmount);
      expect(await pair.getAmountIn(token0.address, expectedOutputAmount)).to.eq(swapAmount);
      await expect(pair.swap(0, expectedOutputAmount.add(2), wallet.address, '0x', overrides)).to.be.revertedWith(
        'Nomiswap: D'
      );
      await pair.swap(0, expectedOutputAmount, wallet.address, '0x', overrides)
    })
  });

  const optimisticTestCases: BigNumber[][] = [
    ['998999999835854396', 5, 10, 1], // given amountIn, amountOut = floor(amountIn * .999)
    ['998999999835854396', 10, 5, 1],
    ['998999999835854396', 5, 5, 1],
    [1, 5, 5, '1001001001165475390'] // given amountOut, amountIn = ceiling(amountOut / .999)
  ].map(a => a.map(n => (typeof n === 'string' ? bigNumberify(n) : expandTo18Decimals(n))));
  optimisticTestCases.forEach((optimisticTestCase, i) => {
    it(`optimistic:${i}`, async () => {
      const [outputAmount, token0Amount, token1Amount, inputAmount] = optimisticTestCase;
      await addLiquidity(token0Amount, token1Amount);
      await token0.transfer(pair.address, inputAmount);
      await expect(pair.swap(outputAmount.add(1), 0, wallet.address, '0x', overrides)).to.be.revertedWith('Nomiswap: D');
      await pair.swap(outputAmount, 0, wallet.address, '0x', overrides)
    })
  });

  it('swap:token0', async () => {
    const token0Amount = expandTo18Decimals(5);
    const token1Amount = expandTo18Decimals(10);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = expandTo18Decimals(1);
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
    const token0Amount = expandTo18Decimals(5);
    const token1Amount = expandTo18Decimals(10);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = expandTo18Decimals(1);
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
    const token0Amount = expandTo18Decimals(5);
    const token1Amount = expandTo18Decimals(10);
    await addLiquidity(token0Amount, token1Amount);

    // ensure that setting price{0,1}CumulativeLast for the first time doesn't affect our gas math
    await mineBlock(provider, (await provider.getBlock('latest')).timestamp + 1);
    await pair.sync(overrides);

    const swapAmount = expandTo18Decimals(1);
    const expectedOutputAmount = bigNumberify('453305446940074565');
    await token1.transfer(pair.address, swapAmount);
    await mineBlock(provider, (await provider.getBlock('latest')).timestamp + 1);
    const tx = await pair.swap(expectedOutputAmount, 0, wallet.address, '0x', overrides);
    const receipt = await tx.wait();
    expect(receipt.gasUsed).to.eq(82849)
  });

  it('burn', async () => {
    const token0Amount = expandTo18Decimals(3);
    const token1Amount = expandTo18Decimals(3);
    await addLiquidity(token0Amount, token1Amount);

    const expectedLiquidity = expandTo18Decimals(6);
    await pair.transfer(pair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY));
    await expect(pair.burn(wallet.address, overrides))
      .to.emit(pair, 'Transfer')
      .withArgs(pair.address, AddressZero, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
      .to.emit(token0, 'Transfer')
      .withArgs(pair.address, wallet.address, token0Amount.sub(500))
      .to.emit(token1, 'Transfer')
      .withArgs(pair.address, wallet.address, token1Amount.sub(500))
      .to.emit(pair, 'Sync')
      .withArgs(500, 500)
      .to.emit(pair, 'Burn')
      .withArgs(wallet.address, token0Amount.sub(500), token1Amount.sub(500), wallet.address);

    expect(await pair.balanceOf(wallet.address)).to.eq(0);
    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY);
    expect(await token0.balanceOf(pair.address)).to.eq(500);
    expect(await token1.balanceOf(pair.address)).to.eq(500);
    const totalSupplyToken0 = await token0.totalSupply();
    const totalSupplyToken1 = await token1.totalSupply();
    expect(await token0.balanceOf(wallet.address)).to.eq(totalSupplyToken0.sub(500));
    expect(await token1.balanceOf(wallet.address)).to.eq(totalSupplyToken1.sub(500));
  });

  it('feeTo:off', async () => {
    const token0Amount = expandTo18Decimals(1000);
    const token1Amount = expandTo18Decimals(1000);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = expandTo18Decimals(1);
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

    const token0Amount = expandTo18Decimals(1000);
    const token1Amount = expandTo18Decimals(1000);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = expandTo18Decimals(1);
    const expectedOutputAmount = await pair.getAmountOut(token1.address, swapAmount);
    await token1.transfer(pair.address, swapAmount);
    await pair.swap(expectedOutputAmount, 0, wallet.address, '0x', overrides);

    const expectedLiquidity = expandTo18Decimals(1000);
    await pair.transfer(pair.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY));
    expect(await pair.adminFee()).to.not.eq(1);
    await pair.burn(wallet.address, overrides);

    expect(await pair.totalSupply()).to.eq(MINIMUM_LIQUIDITY.add('1000000699995921453974'));
    expect(await pair.balanceOf(other.address)).to.not.eq('0');

    // using 1000 here instead of the symbolic MINIMUM_LIQUIDITY because the amounts only happen to be equal...
    // ...because the initial liquidity amounts were equal
    expect(await token0.balanceOf(pair.address)).to.eq(bigNumberify(1000).add('499500677742295696044'));
    expect(await token1.balanceOf(pair.address)).to.eq(bigNumberify(1000).add('500500175173918032844'))
  });

  it('twoSideTransfer', async () => {
    await factory.setSwapFee(pair.address, 0);

    const token0Amount = expandTo18Decimals(1000);
    const token1Amount = expandTo18Decimals(1000);
    await addLiquidity(token0Amount, token1Amount);

    const swapAmount = expandTo18Decimals(800);
    const forwardOut = await pair.getAmountOut(token0.address, swapAmount);
    await token0.transfer(pair.address, swapAmount);

    await pair.swap(0, forwardOut, wallet.address, '0x', overrides);

    const reverseOut = await pair.getAmountOut(token1.address, forwardOut);

    expect(swapAmount.sub(reverseOut).toNumber()).to.be.lessThan(10);

    await token1.transfer(pair.address, forwardOut);

    await pair.swap(reverseOut, 0, wallet.address, '0x', overrides);

  });

  it('case from router test', async () => {
    const token0Amount = expandTo18Decimals(10);
    const token1Amount = expandTo18Decimals(10);
    await addLiquidity(token0Amount, token1Amount);

    const input = "3073608539079599913";
    const output = await pair.getAmountOut(token0.address, input);
    expect(output).to.be.eq("3064468431129174971");
    await token0.transfer(pair.address, input);

    await pair.swap(0, output, wallet.address, '0x', overrides);

  });


});
