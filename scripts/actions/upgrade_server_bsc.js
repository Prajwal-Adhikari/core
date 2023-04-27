const { ethers, upgrades } = require('hardhat');

async function main () {
  const Pool = await ethers.getContractFactory('Pool');
  console.log('Upgrading Pool...');
  await upgrades.upgradeProxy('0xd15Def19E5ACb4d1d47348ddBe3f0644Fb43164D', Pool);
  console.log('Pool upgraded');
}

main();

