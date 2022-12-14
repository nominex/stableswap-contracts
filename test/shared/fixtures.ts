import {Contract} from '@ethersproject/contracts'
import {Wallet} from '@ethersproject/wallet'
import {deployContract, MockProvider} from 'ethereum-waffle'

import {expandTo18Decimals} from './utilities'

import ERC20 from '../../build/contracts/ERC20.json'
import NomiswapFactory from '../../build/contracts/NomiswapStableFactory.json'
import NomiswapPair from '../../build/contracts/NomiswapStablePair.json'

import TestERC20 from '../../build/contracts/TestERC20.json'

interface FactoryFixture {
  factory: Contract
}

const overrides = {
  gasLimit: 9999999
};

export async function factoryFixture([wallet]: Wallet[], _: MockProvider): Promise<FactoryFixture> {
  const factory = await deployContract(wallet, NomiswapFactory, [wallet.address], overrides);
  return { factory }
}

interface PairFixture extends FactoryFixture {
  token0: Contract
  token1: Contract
  pair: Contract
}

export async function pairFixture([wallet]: Wallet[], provider: MockProvider): Promise<PairFixture> {

  const { factory } = await factoryFixture( [wallet], provider);

  const tokenA = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)], overrides);
  const tokenB = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)], overrides);

  await factory.createPair(tokenA.address, tokenB.address, overrides);
  const pairAddress = await factory.getPair(tokenA.address, tokenB.address);
  const pair = new Contract(pairAddress, JSON.stringify(NomiswapPair.abi), provider).connect(wallet);

  const token0Address = (await pair.token0());
  const token0 = tokenA.address === token0Address ? tokenA : tokenB;
  const token1 = tokenA.address === token0Address ? tokenB : tokenA;

  return { factory, token0, token1, pair }
}

export async function pairWithDifferentDecimalsFixture([wallet]: Wallet[], provider: MockProvider): Promise<PairFixture> {

  const { factory } = await factoryFixture( [wallet], provider);

  const tokenA = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)], overrides);
  const tokenB = await deployContract(wallet, TestERC20, [expandTo18Decimals(10000), 6], overrides);

  await factory.createPair(tokenA.address, tokenB.address, overrides);
  const pairAddress = await factory.getPair(tokenA.address, tokenB.address);
  const pair = new Contract(pairAddress, JSON.stringify(NomiswapPair.abi), provider).connect(wallet);

  const token0Address = (await pair.token0());
  const token0 = tokenA.address === token0Address ? tokenA : tokenB;
  const token1 = tokenA.address === token0Address ? tokenB : tokenA;

  return { factory, token0, token1, pair }
}
