const NomiswapFactory = artifacts.require('NomiswapFactory')

module.exports = async function (deployer, network, accounts) {
  // Deploy the NomiswapFactory contract as our only task
  await deployer.deploy(NomiswapFactory, accounts[0])

  const nomiswapFactory = await NomiswapFactory.deployed()
  console.log('NomiswapFactory deployed with ', await nomiswapFactory.INIT_CODE_HASH(), "init code hash");
  const swapFeeReciever = '0x993439e65D78412B27568605CDadd04A3C582ddb';
  await nomiswapFactory.setFeeTo(swapFeeReciever);
}