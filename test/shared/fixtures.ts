import { Contract } from '@ethersproject/contracts'
import { Wallet } from '@ethersproject/wallet'
import { Web3Provider } from 'ethers/providers'
import { deployContract, link } from 'ethereum-waffle'
import { MockProvider } from 'ethereum-waffle'

import { expandTo18Decimals } from './utilities'

import ERC20 from '../../build/ERC20.json'
import FactoryLib from '../../build/FactoryLib.json'
import NomiswapFactory from '../../build/StableSwapFactory.json'
import NomiswapPair from '../../build/StableSwapPair.json'

interface FactoryFixture {
  factory: Contract
}

const overrides = {
  gasLimit: 9999999
}

let library: Contract;

export async function factoryFixture([wallet]: Wallet[], _: MockProvider): Promise<FactoryFixture> {
  if (!library) {
    library = await deployContract(wallet, FactoryLib, []);
    link(NomiswapFactory, 'contracts/FactoryLib.sol:FactoryLib', library.address);
  }

  const factory = await deployContract(wallet, NomiswapFactory, [wallet.address]);
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
  const pairAddress = await factory.getPair(tokenA.address, tokenB.address)
  const pair = new Contract(pairAddress, JSON.stringify(NomiswapPair.abi), provider).connect(wallet)

  const token0Address = (await pair.token0())
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  return { factory, token0, token1, pair }
}
