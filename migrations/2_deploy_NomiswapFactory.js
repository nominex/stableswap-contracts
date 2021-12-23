const NomiswapFactory = artifacts.require('NomiswapFactory')

module.exports = async function (deployer, network, accounts) {
  // Deploy the NomiswapFactory contract as our only task
  await deployer.deploy(NomiswapFactory, accounts[0])

  const nomiswapFactoryInstance = await NomiswapFactory.deployed()

  await nomiswapFactoryInstance.setFeeTo(accounts[0])
}