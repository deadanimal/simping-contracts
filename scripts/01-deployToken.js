const hre = require("hardhat");

async function main() {

  const SimpingToken = await hre.ethers.getContractFactory("SimpingToken");
  const simpingToken = await SimpingToken.deploy();
  await simpingToken.deployed();
  console.log("SimpingToken deployed to:", simpingToken.address);

  const SimpingGovernor = await hre.ethers.getContractFactory("SimpingGovernor");
  const simpingGovernor = await SimpingGovernor.deploy(simpingToken.address);
  await simpingGovernor.deployed(); 
  console.log("SimpingGovernor deployed to:", simpingGovernor.address); 


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
