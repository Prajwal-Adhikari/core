const { ethers, upgrades } = require('hardhat');

async function main () {
  const PoolV2 = await ethers.getContractFactory('PoolV2');
  console.log('Upgrading Pool...');
  await upgrades.upgradeProxy('0x48648C81DE8FDf6389C2Adb5D22F247C3706f747', PoolV2);
  console.log('Pool upgraded');
}

main();