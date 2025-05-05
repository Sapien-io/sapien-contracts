// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../interfaces/IPoolAdapter.sol";

/**
 * @title UniswapPoolAdapter
 * @notice Adapter for handling LP token deposits and withdrawals with Uniswap V2
 */
contract UniswapPoolAdapter is IPoolAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Uniswap V2 Router contract
    IUniswapV2Router02 public immutable router;

    /// @notice The Uniswap V2 Pair contract for the LP token
    IUniswapV2Pair public immutable pair;

    /// @notice The token0 of the pair
    IERC20 public immutable token0;

    /// @notice The token1 of the pair
    IERC20 public immutable token1;

    /**
     * @notice Constructor for the Uniswap pool adapter
     * @param router_ The address of the Uniswap V2 Router
     * @param pair_ The address of the Uniswap V2 Pair
     */
    constructor(address router_, address pair_) {
        require(router_ != address(0), "Zero address not allowed for router");
        require(pair_ != address(0), "Zero address not allowed for pair");

        router = IUniswapV2Router02(router_);
        pair = IUniswapV2Pair(pair_);
        
        token0 = IERC20(IUniswapV2Pair(pair_).token0());
        token1 = IERC20(IUniswapV2Pair(pair_).token1());
    }

    /**
     * @notice Deposits LP tokens into the pool
     * @param user The address of the user depositing LP tokens
     * @param amount The amount of LP tokens to deposit
     * @return success True if the deposit was successful
     */
    function depositLP(address user, uint256 amount) external override returns (bool) {
        require(user != address(0), "Zero address not allowed for user");
        require(amount > 0, "Amount must be greater than zero");

        // Transfer LP tokens from user to this contract
        IERC20(address(pair)).safeTransferFrom(user, address(this), amount);

        // Approve router to spend LP tokens
        IERC20(address(pair)).approve(address(router), amount);

        // Remove liquidity
        (uint256 amount0, uint256 amount1) = router.removeLiquidity(
            address(token0),
            address(token1),
            amount,
            0, // Accept any amount of slippage
            0, // Accept any amount of slippage
            user,
            block.timestamp
        );

        return amount0 > 0 && amount1 > 0;
    }

    /**
     * @notice Withdraws LP tokens from the pool
     * @param user The address of the user withdrawing LP tokens
     * @param amount The amount of LP tokens to withdraw
     * @return success True if the withdrawal was successful
     */
    function withdrawLP(address user, uint256 amount) external override returns (bool) {
        require(user != address(0), "Zero address not allowed for user");
        require(amount > 0, "Amount must be greater than zero");

        // Get reserves
        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        require(reserve0 > 0 && reserve1 > 0, "No liquidity in pool");

        // Calculate amounts of tokens needed
        uint256 totalSupply = pair.totalSupply();
        uint256 amount0 = (amount * reserve0) / totalSupply;
        uint256 amount1 = (amount * reserve1) / totalSupply;

        // Transfer tokens from user to this contract
        token0.safeTransferFrom(user, address(this), amount0);
        token1.safeTransferFrom(user, address(this), amount1);

        // Approve router to spend tokens
        token0.approve(address(router), amount0);
        token1.approve(address(router), amount1);

        // Add liquidity
        (,, uint256 liquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            amount0,
            amount1,
            0, // Accept any amount of slippage
            0, // Accept any amount of slippage
            user,
            block.timestamp
        );

        return liquidity > 0;
    }
} 