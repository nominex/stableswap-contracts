import { Contract } from '@ethersproject/contracts'
import { Web3Provider } from '@ethersproject/providers'
import {
  BigNumber,
  bigNumberify,
  getAddress,
  getCreate2Address,
  keccak256,
  defaultAbiCoder,
  toUtf8Bytes,
  solidityPack,
  solidityKeccak256,
  AbiCoder
} from 'ethers/utils'
import { pack } from 'ethers/utils/solidity'

const PERMIT_TYPEHASH = keccak256(
  toUtf8Bytes('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)')
)

export function expandTo18Decimals(n: number): BigNumber {
  return bigNumberify(n).mul(bigNumberify(10).pow(18))
}

function getDomainSeparator(name: string, tokenAddress: string, chainId: number) {
  return keccak256(
    defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        keccak256(toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
        keccak256(toUtf8Bytes(name)),
        keccak256(toUtf8Bytes('1')),
        chainId,
        tokenAddress
      ]
    )
  )
}

export function getPairAddress(
  factoryAddress: string,
  [tokenA, tokenB]: [string, string],
  creationCode: string
): string {
  const [token0, token1] = tokenA < tokenB ? [tokenA, tokenB] : [tokenB, tokenA]
  const saltHex = keccak256(solidityPack(['address', 'address'], [token0, token1]));
  const bytecode = buildBytecode(['address', 'address'], [token0, token1], creationCode);
  return getCreate2Address({"from": factoryAddress, "salt": saltHex, "initCode": bytecode})
  }

function buildBytecode(
  constructorTypes: any[],
  constructorArgs: any[],
  contractBytecode: string,
) {
  return `${contractBytecode}${defaultAbiCoder.encode(constructorTypes, constructorArgs).slice(
    2,
  )}`
}

export async function getApprovalDigest(
  token: Contract,
  approve: {
    owner: string
    spender: string
    value: BigNumber
  },
  nonce: BigNumber,
  deadline: BigNumber
): Promise<string> {
  const network = await token.provider.getNetwork();
  const name = await token.name();
  const DOMAIN_SEPARATOR = getDomainSeparator(name, token.address, network.chainId);
  return keccak256(
    solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        DOMAIN_SEPARATOR,
        keccak256(
          defaultAbiCoder.encode(
            ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
            [PERMIT_TYPEHASH, approve.owner, approve.spender, approve.value, nonce, deadline]
          )
        )
      ]
    )
  )
}

export async function mineBlock(provider: Web3Provider, timestamp: number): Promise<void> {
  await new Promise(async (resolve, reject) => {
    ;(provider.provider.sendAsync as any)(
      { jsonrpc: '2.0', method: 'evm_mine', params: [timestamp] },
      (error: any, result: any): void => {
        if (error) {
          reject(error)
        } else {
          resolve(result)
        }
      }
    )
  })
}

export function encodePrice(reserve0: BigNumber, reserve1: BigNumber) {
  return [reserve1.mul(bigNumberify(2).pow(112)).div(reserve0), reserve0.mul(bigNumberify(2).pow(112)).div(reserve1)]
}
