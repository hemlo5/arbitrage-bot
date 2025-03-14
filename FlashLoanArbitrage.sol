// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { IPool } from "@aave/core-v3/contracts/interfaces/IPool.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FlashLoanArbitrage is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Aave flashloan pool address on Arbitrum
    address public immutable aavePool;
    // Uniswap V3 router on Arbitrum
    ISwapRouter public immutable uniswapRouter;
    // SushiSwap V3 router on Arbitrum
    ISwapRouter public immutable sushiswapRouter;
    // Tokens for trading (e.g., tokenA = ARB, tokenB = WETH)
    address public immutable tokenA;
    address public immutable tokenB;
    // Address to receive profits
    address public profitReceiver;

    event ArbitrageExecuted(uint256 profit, bool success);

    struct ArbitrageParams {
        bool direction;       // True: SushiSwap V3 first, False: Uniswap V3 first
        uint256 minAmountOut1; // Minimum output for first swap
        uint256 minAmountOut2; // Minimum output for second swap
        uint256 deadline;      // Transaction deadline (unix timestamp)
        uint24 fee1;           // Fee for first swap (SushiSwap V3 or Uniswap V3)
        uint24 fee2;           // Fee for second swap (Uniswap V3 or SushiSwap V3)
    }

    constructor(
        address _aavePool,
        address _uniswapRouter,
        address _sushiswapRouter,
        address _tokenA,
        address _tokenB,
        address _profitReceiver
    ) {
        aavePool = _aavePool;
        uniswapRouter = ISwapRouter(_uniswapRouter);
        sushiswapRouter = ISwapRouter(_sushiswapRouter);
        tokenA = _tokenA;
        tokenB = _tokenB;
        profitReceiver = _profitReceiver;
    }

    /// @notice Updates the profit receiver address
    function setProfitReceiver(address _profitReceiver) external onlyOwner {
        require(_profitReceiver != address(0), "Invalid address");
        profitReceiver = _profitReceiver;
    }

    /// @notice Initiates a flashloan arbitrage trade
    /// @param token The token to flashloan (e.g., ARB)
    /// @param amount The amount to flashloan
    /// @param direction True: SushiSwap V3 -> Uniswap V3, False: Uniswap V3 -> SushiSwap V3
    /// @param minAmountOut1 Minimum output amount from the first swap
    /// @param minAmountOut2 Minimum output amount from the second swap
    /// @param deadline Deadline for the swap execution
    /// @param fee1 Fee tier for the first swap
    /// @param fee2 Fee tier for the second swap
    function executeArbitrage(
        address token,
        uint256 amount,
        bool direction,
        uint256 minAmountOut1,
        uint256 minAmountOut2,
        uint256 deadline,
        uint24 fee1,
        uint24 fee2
    ) external onlyOwner nonReentrant {
        ArbitrageParams memory params = ArbitrageParams(
            direction,
            minAmountOut1,
            minAmountOut2,
            deadline,
            fee1,
            fee2
        );
        IPool(aavePool).flashLoanSimple(address(this), token, amount, abi.encode(params), 0);
    }

    /// @notice Called by Aave after granting the flashloan
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == aavePool, "Unauthorized");
        require(initiator == address(this), "Invalid initiator");

        ArbitrageParams memory arbParams = abi.decode(params, (ArbitrageParams));

        // Determine the output token for the first swap
        address outputToken = (asset == tokenA) ? tokenB : tokenA;

        // First swap: SushiSwap V3 if direction=true, Uniswap V3 if false
        uint256 received;
        if (arbParams.direction) {
            // SushiSwap V3 swap
            received = swapV3(sushiswapRouter, asset, amount, outputToken, arbParams.minAmountOut1, arbParams.deadline, arbParams.fee1);
        } else {
            // Uniswap V3 swap
            received = swapV3(uniswapRouter, asset, amount, outputToken, arbParams.minAmountOut1, arbParams.deadline, arbParams.fee1);
        }

        // Second swap: Opposite DEX
        uint256 finalAmount;
        if (arbParams.direction) {
            // Uniswap V3 swap
            finalAmount = swapV3(uniswapRouter, outputToken, received, asset, arbParams.minAmountOut2, arbParams.deadline, arbParams.fee2);
        } else {
            // SushiSwap V3 swap
            finalAmount = swapV3(sushiswapRouter, outputToken, received, asset, arbParams.minAmountOut2, arbParams.deadline, arbParams.fee2);
        }

        uint256 totalDebt = amount + premium;
        require(finalAmount > totalDebt, "Not profitable");

        // Repay the flashloan
        IERC20(asset).safeTransfer(aavePool, totalDebt);

        // Send profit to receiver
        uint256 profit = finalAmount - totalDebt;
        IERC20(asset).safeTransfer(profitReceiver, profit);

        emit ArbitrageExecuted(profit, true);
        return true;
    }

    /// @notice Executes a swap on a V3 DEX (Uniswap V3 or SushiSwap V3)
    function swapV3(
        ISwapRouter router,
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 deadline,
        uint24 poolFee
    ) internal returns (uint256) {
        require(amountIn > 0, "Zero amount");
        require(deadline >= block.timestamp, "Expired deadline");

        // Approve the router to spend tokenIn
        IERC20(tokenIn).safeApprove(address(router), 0);
        IERC20(tokenIn).safeApprove(address(router), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: address(this),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        return router.exactInputSingle(params);
    }
}
