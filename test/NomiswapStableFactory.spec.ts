import chai, { expect } from 'chai'
import { Contract } from '@ethersproject/contracts'
import { AddressZero } from 'ethers/constants'
import { bigNumberify } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader, Fixture, deployContract } from 'ethereum-waffle'

import { expandTo18Decimals, getPairAddress } from './shared/utilities'
import { factoryFixture } from './shared/fixtures'

import NomiswapStablePair from '../build/contracts/NomiswapStablePair.json'
import ERC20 from '../build/contracts/ERC20.json';
chai.use(solidity)

const TOTAL_SUPPLY = expandTo18Decimals(10000);

const TEST_ADDRESSES: [string, string] = [
  '0x1000000000000000000000000000000000000001',
  '0x2000000000000000000000000000000000000002'
]

describe('NomiswapFactory', () => {
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
  const loadFixture: <T>(fixture: Fixture<T>) => Promise<T> = createFixtureLoader( [wallet, other], provider);

  let factory: Contract;
  beforeEach(async () => {
    const fixture = await loadFixture(factoryFixture);
    factory = fixture.factory;
    let token0 = await deployContract(wallet, ERC20, [TOTAL_SUPPLY]);
    let token1 = await deployContract(wallet, ERC20, [TOTAL_SUPPLY]);
    if (token1.address < token0.address) {
      TEST_ADDRESSES[0] = token1.address;
      TEST_ADDRESSES[1] = token0.address;
    } else {
      TEST_ADDRESSES[0] = token0.address;
      TEST_ADDRESSES[1] = token1.address;
    }
  });

  it('feeTo, feeToSetter, allPairsLength', async () => {
    expect(await factory.feeTo()).to.eq(AddressZero)
    expect(await factory.feeToSetter()).to.eq(wallet.address)
    expect(await factory.allPairsLength()).to.eq(0)
  });

  async function createPair(tokens: [string, string]) {
    const bytecode = `${NomiswapStablePair.bytecode}`
    const create2Address = getPairAddress(factory.address, tokens, bytecode)
    await expect(factory.createPair(...tokens))
      .to.emit(factory, 'PairCreated')
      .withArgs(TEST_ADDRESSES[0], TEST_ADDRESSES[1], create2Address, bigNumberify(1))

    await expect(factory.createPair(...tokens)).to.be.reverted // Nomiswap: PAIR_EXISTS
    await expect(factory.createPair(...tokens.slice().reverse())).to.be.reverted // Nomiswap: PAIR_EXISTS
    expect(await factory.getPair(...tokens)).to.eq(create2Address)
    expect(await factory.getPair(...tokens.slice().reverse())).to.eq(create2Address)
    expect(await factory.allPairs(0)).to.eq(create2Address)
    expect(await factory.allPairsLength()).to.eq(1)

    const pair = new Contract(create2Address, JSON.stringify(NomiswapStablePair.abi), provider)
    expect(await pair.factory()).to.eq(factory.address)
    expect(await pair.token0()).to.eq(TEST_ADDRESSES[0])
    expect(await pair.token1()).to.eq(TEST_ADDRESSES[1])
  }

  it('createPair', async () => {
    await createPair(TEST_ADDRESSES)
  });

  it('createPair:reverse', async () => {
    await createPair(TEST_ADDRESSES.slice().reverse() as [string, string])
  });

  it('createPair:gas', async () => {
    const tx = await factory.createPair(...TEST_ADDRESSES);
    const receipt = await tx.wait();
    expect(receipt.gasUsed).to.eq(3861643)
  });

  it('setFeeTo', async () => {
    await expect(factory.connect(other).setFeeTo(other.address)).to.be.revertedWith('Nomiswap: FORBIDDEN');
    await factory.setFeeTo(wallet.address);
    expect(await factory.feeTo()).to.eq(wallet.address)
  });

  it('setFeeToSetter', async () => {
    await expect(factory.connect(other).setFeeToSetter(other.address)).to.be.revertedWith('Nomiswap: FORBIDDEN');
    await factory.setFeeToSetter(other.address);
    expect(await factory.feeToSetter()).to.eq(other.address);
    await expect(factory.setFeeToSetter(wallet.address)).to.be.revertedWith('Nomiswap: FORBIDDEN')
  })
});
