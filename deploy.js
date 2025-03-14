const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Aave V3 Pool Address on Arbitrum
  const aavePoolAddress = "0x794a61358D6845594F94dc1DB02A252b5b4814aD"; // Aave Pool

  // Uniswap V3 Router Address on Arbitrum
  const uniswapRouterAddress = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"; // Uniswap V3 Router

  // SushiSwap V3 Router Address on Arbitrum
  const sushiswapRouterAddress = "0x85CD07Ea01423b1E937929B44E4Ad8c40BbB5E71"; // SushiSwap V3 Router

  // WETH & ARB Token Addresses on Arbitrum
  const wethAddress = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"; // WETH on Arbitrum
  const arbAddress = "0x912CE59144191C1204E64559FE8253a0e49E6548"; // ARB on Arbitrum

  // Set the profit receiver (your wallet address)
  const profitReceiver = deployer.address;

  // Get the contract factory for FlashLoanArbitrage
  const FlashLoanArbitrage = await hre.ethers.getContractFactory("FlashLoanArbitrage");

  // Deploy the contract with the required parameters
  const flashLoanArbitrage = await FlashLoanArbitrage.deploy(
    aavePoolAddress,
    uniswapRouterAddress,
    sushiswapRouterAddress,
    arbAddress,
    wethAddress,
    profitReceiver
  );

  // Wait for the deployment transaction to be mined
  await flashLoanArbitrage.waitForDeployment();

  // Log the contract address
  console.log("FlashLoanArbitrage deployed to:", flashLoanArbitrage.target);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});