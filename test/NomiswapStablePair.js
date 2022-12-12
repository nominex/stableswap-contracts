const ERC20 = artifacts.require('ERC20');
const Factory = artifacts.require('NomiswapStableFactory');
const Pair = artifacts.require('NomiswapStablePair');

contract('NomiswapPair', (accounts) => {

  let tokenA;
  let tokenB;
  let factory;
  let pair;

  beforeEach(async () => {
    tokenA = await ERC20.new('1000000000000000000000000000000');
    tokenB = await ERC20.new('1000000000000000000000000000000');
    factory = await Factory.new(accounts[0]);
    await factory.createPair(tokenA.address, tokenB.address);
    pair = await Pair.at(await factory.getPair(tokenA.address, tokenB.address));
    await tokenA.transfer(pair.address, '3705319258315779612811537')
    await tokenB.transfer(pair.address, '897737256085882746125498')
    await pair.mint(accounts[0])
  })

  it('correct amount out for A = 1.01', async () => {
    const now = await currentTime();
    await factory.rampA(pair.address, '100', now + 60 * 60 * 24);
    await advanceTime(60 * 60 * 24 - 10);
    await advanceBlock();
    const actualA = await pair.getA();
    assert(actualA.eq(web3.utils.toBN('101')), `unexpected A: ${actualA.toString()}`)
    const amountIn = web3.utils.toBN('1000000000000000000');
    const tokenAAmountOut = await pair.getAmountOut.call(tokenB.address, amountIn);
    assertOutputAmount('1862347186150963958', tokenAAmountOut, 'tokenAAmountOut')
    const tokenBAmountOut = await pair.getAmountOut.call(tokenA.address, amountIn);
    assertOutputAmount('535883009194457292', tokenBAmountOut, 'tokenBAmountOut')
  })

  it('correct amount out for A = 85.00', async () => {
    const actualA = await pair.getA();
    assert(actualA.eq(web3.utils.toBN('8500')), `unexpected A: ${actualA}`)
    const amountIn = web3.utils.toBN('1000000000000000000');
    const tokenAAmountOut = await pair.getAmountOut.call(tokenB.address, amountIn);
    assertOutputAmount('1016980173063479735', tokenAAmountOut, 'tokenAAmountOut')
    const tokenBAmountOut = await pair.getAmountOut.call(tokenA.address, amountIn);
    assertOutputAmount('981337674305026236', tokenBAmountOut, 'tokenBAmountOut')
  })

  it('correct amount out for A = 564.28', async () => {
    const now = await currentTime();
    await factory.rampA(pair.address, '200000', now + 60 * 60 * 24 + 86400);
    await advanceTime(60 * 60 * 12 + 48);
    await advanceBlock();
    const actualA = await pair.getA();
    assert(actualA.eq(web3.utils.toBN('56428')), `unexpected A: ${actualA.toString()}`)
    const amountIn = web3.utils.toBN('1000000000000000000');
    const tokenAAmountOut = await pair.getAmountOut.call(tokenB.address, amountIn);
    assertOutputAmount('1001733696521897387', tokenAAmountOut, 'tokenAAmountOut')
    const tokenBAmountOut = await pair.getAmountOut.call(tokenA.address, amountIn);
    assertOutputAmount('996273756805616913', tokenBAmountOut, 'tokenBAmountOut')
  })

  it('no overflow for A = 200000.00 and tvl about 50b', async () => {
    let now = await currentTime();
    await factory.rampA(pair.address, '200000', now + 60 * 60 * 24);
    await advanceTime(60 * 60 * 24);
    await advanceBlock();
  
    now = await currentTime();
    await factory.rampA(pair.address, '2000000', now + 60 * 60 * 24);
    await advanceTime(60 * 60 * 24);
    await advanceBlock();

    now = await currentTime();
    await factory.rampA(pair.address, '20000000', now + 60 * 60 * 24);
    await advanceTime(60 * 60 * 24);
    await advanceBlock();

    const actualA = await pair.getA();
    assert(actualA.eq(web3.utils.toBN('20000000')), `unexpected A: ${actualA.toString()}`)
    await tokenA.transfer(pair.address, '37053192583157796128115370000')
    await tokenB.transfer(pair.address, '8977372560858827461254980000')
    await pair.mint(accounts[0])
    const amountIn = web3.utils.toBN('1000000000000000000');
    const tokenAAmountOut = await pair.getAmountOut.call(tokenB.address, amountIn);
    assertOutputAmount('999007725486704473', tokenAAmountOut, 'tokenAAmountOut')
    const tokenBAmountOut = await pair.getAmountOut.call(tokenA.address, amountIn);
    assertOutputAmount('998992274244747432', tokenBAmountOut, 'tokenBAmountOut')
  })

  advanceTime = (time) => {
    return new Promise((resolve, reject) => {
      web3.currentProvider.send({
        jsonrpc: '2.0',
        method: 'evm_increaseTime',
        params: [time],
        id: new Date().getTime()
      }, (err, result) => {
        if (err) { return reject(err) }
        return resolve(result)
      })
    })
  }

  advanceBlock = () => {
    return new Promise((resolve, reject) => {
      web3.currentProvider.send({
        jsonrpc: '2.0',
        method: 'evm_mine',
        id: new Date().getTime()
      }, (err, result) => {
        if (err) { return reject(err) }
        const newBlockHash = web3.eth.getBlock('latest').hash

        return resolve(newBlockHash)
      })
    })
  }

  currentTime = async () => web3.eth.getBlockNumber().then(web3.eth.getBlock).then(block => block.timestamp)

  function assertOutputAmount(expected, actual, msgId) {
    expected = web3.utils.toBN(expected)
    assert(actual.eq(expected), `expected amount ${expected.toString()} <> actual ${actual.toString()} (${msgId})`)
  }

})
