// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IPoolAdapter.sol";

/**
 * @title AerodromePoolAdapter
 * @notice Adapter for handling LP token deposits and withdrawals with Aerodrome
 */
contract AerodromePoolAdapter is IPoolAdapter {
    using SafeERC20 for IERC20;

    /// @notice The Aerodrome Router contract
    address public immutable router;

    /// @notice The Aerodrome Pair contract for the LP token
    address public immutable pair;

    /// @notice The token0 of the pair
    IERC20 public immutable token0;

    /// @notice The token1 of the pair
    IERC20 public immutable token1;

    /**
     * @notice Constructor for the Aerodrome pool adapter
     * @param router_ The address of the Aerodrome Router
     * @param pair_ The address of the Aerodrome Pair
     */
    constructor(address router_, address pair_) {
        require(router_ != address(0), "Zero address not allowed for router");
        require(pair_ != address(0), "Zero address not allowed for pair");

        router = router_;
        pair = pair_;
        
        // Get token addresses from the pair
        (bool success, bytes memory data) = pair_.staticcall(abi.encodeWithSignature("token0()"));
        require(success, "Failed to get token0");
        token0 = IERC20(abi.decode(data, (address)));

        (success, data) = pair_.staticcall(abi.encodeWithSignature("token1()"));
        require(success, "Failed to get token1");
        token1 = IERC20(abi.decode(data, (address)));
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
        IERC20(pair).safeTransferFrom(user, address(this), amount);

        // Approve router to spend LP tokens
        IERC20(pair).approve(address(router), amount);

        // Remove liquidity
        (bool success,) = router.call(
            abi.encodeWithSignature(
                "removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)",
                address(token0),
                address(token1),
                amount,
                0, // Accept any amount of slippage
                0, // Accept any amount of slippage
                user,
                block.timestamp
            )
        );

        return success;
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
        (bool success, bytes memory data) = pair.staticcall(abi.encodeWithSignature("getReserves()"));
        require(success, "Failed to get reserves");
        (uint256 reserve0, uint256 reserve1,) = abi.decode(data, (uint256, uint256, uint32));
        require(reserve0 > 0 && reserve1 > 0, "No liquidity in pool");

        // Get total supply
        (success, data) = pair.staticcall(abi.encodeWithSignature("totalSupply()"));
        require(success, "Failed to get total supply");
        uint256 totalSupply = abi.decode(data, (uint256));

        // Calculate amounts of tokens needed
        uint256 amount0 = (amount * reserve0) / totalSupply;
        uint256 amount1 = (amount * reserve1) / totalSupply;

        // Transfer tokens from user to this contract
        token0.safeTransferFrom(user, address(this), amount0);
        token1.safeTransferFrom(user, address(this), amount1);

        // Approve router to spend tokens
        token0.approve(address(router), amount0);
        token1.approve(address(router), amount1);

        // Add liquidity
        (success,) = router.call(
            abi.encodeWithSignature(
                "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)",
                address(token0),
                address(token1),
                amount0,
                amount1,
                0, // Accept any amount of slippage
                0, // Accept any amount of slippage
                user,
                block.timestamp
            )
        );

        return success;
    }
} 