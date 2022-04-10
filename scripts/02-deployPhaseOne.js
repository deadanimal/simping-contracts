const hre = require("hardhat");

async function main() {

  const factoryFee = ethers.utils.parseUnits("0.1", 18);

  const Factory = await hre.ethers.getContractFactory("Factory");
  const factory = await Factory.deploy(factoryFee);
  await factory.deployed();
  console.log("Factory deployed to:", factory.address);


  const registrarAddress = "0x453240AE09c13Df8BF69E998574369F7367D43d5";


  const cancelFee = ethers.utils.parseUnits("1.0", 18);
  const commissionFee = 500; // 500 out of 10,000 which is 5.0%
  const minimumPrice = ethers.utils.parseUnits("10.0", 18);

  const Market = await hre.ethers.getContractFactory("Market");
  const marketr = await Market.deploy(
      factory.address,
      registrarAddress,
      cancelFee,
      commissionFee,
      minimumPrice
  );
  await marketr.deployed(); 
  console.log("Market deployed to:", marketr.address); 


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
