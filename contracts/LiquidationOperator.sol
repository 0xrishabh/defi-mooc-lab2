//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "hardhat/console.sol";

// ----------------------INTERFACE------------------------------

// Aave
// https://docs.aave.com/developers/the-core-protocol/lendingpool/ilendingpool

interface ILendingPool {
    /**
     * Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1
     * - The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives
     *   a proportionally amount of the `collateralAsset` plus a bonus to cover market risk
     * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of theliquidation
     * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
     * @param user The address of the borrower getting liquidated
     * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
     * @param receiveAToken `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants
     * to receive the underlying collateral asset directly
     **/
    function liquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;

    /**
     * Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return currentLiquidationThreshold the liquidation threshold of the user
     * @return ltv the loan to value of the user
     * @return healthFactor the current health factor of the user
     **/
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

// UniswapV2

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IERC20.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/Pair-ERC-20
interface IERC20 {
    // Returns the account balance of another account with address _owner.
    function balanceOf(address owner) external view returns (uint256);

    /**
     * Allows _spender to withdraw from your account multiple times, up to the _value amount.
     * If this function is called again it overwrites the current allowance with _value.
     * Lets msg.sender set their allowance for a spender.
     **/
    function approve(address spender, uint256 value) external; // return type is deleted to be compatible with USDT

    /**
     * Transfers _value amount of tokens to address _to, and MUST fire the Transfer event.
     * The function SHOULD throw if the message caller’s account balance does not have enough tokens to spend.
     * Lets msg.sender send pool tokens to an address.
     **/
    function transfer(address to, uint256 value) external returns (bool);
}

// https://github.com/Uniswap/v2-periphery/blob/master/contracts/interfaces/IWETH.sol
interface IWETH is IERC20 {
    // Convert the wrapped token back to Ether.
    function withdraw(uint256) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Callee.sol
// The flash loan liquidator we plan to implement this time should be a UniswapV2 Callee
interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/factory
interface IUniswapV2Factory {
    // Returns the address of the pair for tokenA and tokenB, if it has been created, else address(0).
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}
interface ICurvePool {
    function exchange(
        int128 i,        // Index value of the from token in the pool
        int128 j,        // Index value of the to token in the pool
        uint256 dx,      // Amount of `from` token to exchange
        uint256 min_dy   // Minimum amount of `to` token expected to receive
    ) external;

    function get_dy(
        int128 i,        // Index value of the from token in the pool
        int128 j,        // Index value of the to token in the pool
        uint256 dy       // Desired amount of `to` token (USDT)
    ) external view returns (uint256);
}

// https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/pair
interface IUniswapV2Pair {
    /**
     * Swaps tokens. For regular swaps, data.length must be 0.
     * Also see [Flash Swaps](https://docs.uniswap.org/protocol/V2/concepts/core-concepts/flash-swaps).
     **/
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /**
     * Returns the reserves of token0 and token1 used to price trades and distribute liquidity.
     * See Pricing[https://docs.uniswap.org/protocol/V2/concepts/advanced-topics/pricing].
     * Also returns the block.timestamp (mod 2**32) of the last block during which an interaction occured for the pair.
     **/
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

// ----------------------IMPLEMENTATION------------------------------

contract LiquidationOperator is IUniswapV2Callee {
    uint8 public constant health_factor_decimals = 18;

    // TODO: define constants used in the contract including ERC-20 tokens, Uniswap Pairs, Aave lending pools, etc. */
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant AAVE = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    address public constant CURVE = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address public constant factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant target = 0x59CE4a2AC5bC3f5F225439B2993b86B42f6d3e9F;
    address immutable owner;
    // END TODO

    // some helper function, it is totally fine if you can finish the lab without using these function
    // https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // some helper function, it is totally fine if you can finish the lab without using these function
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    // safe mul is not necessary since https://docs.soliditylang.org/en/v0.8.9/080-breaking-changes.html
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {}


    // required by the testing script, entry for your liquidation call
    function operate() external {


        // 0. security checks and initializing variables
        //    *** Your code here ***

        // 1. get the target user account data & make sure it is liquidatable

        (uint256 totalCollateralETH, uint256 totalDebtETH, , , , uint256 healthFactor) = ILendingPool(AAVE).getUserAccountData(
            target
        );
        require(healthFactor < 1e18, "Health factor is not below 1");

        // 2. call flash swap to liquidate the target user
        // based on https://etherscan.io/tx/0xac7df37a43fab1b130318bbb761861b8357650db2e2c6493b73d6da3d9581077
        // we know that the target user borrowed USDT with WBTC as collateral
        // we should borrow USDT, liquidate the target user and get the WBTC, then swap WBTC to repay uniswap
        // (please feel free to develop other workflows as long as they liquidate the target user successfully)
        //    *** Your code here ***

        uint256 amountToLiquidate = 2919714318466;
        uint256 amountInUSDC = ICurvePool(CURVE).get_dy(
            1,
            2,
            amountToLiquidate
        );
        address poolETH_USDC = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;//IUniswapV2Factory(factory).getPair(WETH, USDC);
        (uint reserve0, uint reserve1, ) = IUniswapV2Pair(poolETH_USDC).getReserves();
        uint256 ETH_USDC_amountETHIn = getAmountIn(amountToLiquidate, reserve1, reserve0); //check token0 and 1


        IUniswapV2Pair(poolETH_USDC).swap(amountInUSDC, 0, address(this), abi.encodePacked(ETH_USDC_amountETHIn));

        // 3. Convert the profit into ETH and send back to sender

        uint256 profit = IERC20(WETH).balanceOf(address(this));
        IWETH(WETH).withdraw(profit);
        payable(owner).transfer(profit);

    }

    // required by the swap
    function uniswapV2Call(
        address,
        uint256 amount0,
        uint256,
        bytes calldata data
    ) external override {
        uint256 amountToRepay = abi.decode(data, (uint256));

        // 2.0. security checks and initializing variables
        IERC20(USDC).approve(CURVE, amount0);
        ICurvePool(CURVE).exchange(
            1,
            2,
            amount0,
            0
        );

        uint256 liquidate = IERC20(USDT).balanceOf(address(this));
        // 2.1 liquidate the target user
        IERC20(USDT).approve(AAVE, liquidate);
        ILendingPool(AAVE).liquidationCall(
            WBTC,
            USDT,
            target,
            liquidate,
            false
        );

        uint256 amountWBTC = IERC20(WBTC).balanceOf(address(this));

        // 2.2 swap WBTC for other things or repay directly
        address poolETH_WBTC = 0xCEfF51756c56CeFFCA006cD410B03FFC46dd3a58; //IUniswapV2Factory(factory).getPair(WETH, WBTC);

        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(poolETH_WBTC).getReserves();

        uint256 amountTakenETH = getAmountOut(amountWBTC, reserve0, reserve1);
        IERC20(WBTC).transfer(poolETH_WBTC, amountWBTC);
        IUniswapV2Pair(poolETH_WBTC).swap(0, amountTakenETH, address(this), new bytes(0));

        // 2.3 repay
        IERC20(WETH).transfer(msg.sender, amountToRepay);
    }
}











// All this is left intentionally


// uint256 amountToLiquidate = ((totalDebtETH * 2000 * 1e6)/1e18);
// address poolUSDT_USDC = IUniswapV2Factory(factory).getPair(USDT, USDC);
// (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(poolUSDT_USDC).getReserves();
// uint256 USDT_USDC_amountUSDCIn = getAmountIn(amountToLiquidate, reserve0, reserve1); //check token0 and 1
// console.log("USDC amount calculated: ", USDT_USDC_amountUSDCIn);

// address poolETH_USDC = IUniswapV2Factory(factory).getPair(WETH, USDC);
// (reserve0, reserve1, ) = IUniswapV2Pair(poolETH_USDC).getReserves();
// uint256 ETH_USDC_amountETHIn = getAmountIn(USDT_USDC_amountUSDCIn, reserve1, reserve0); //check token0 and 1
// console.log("Reserve0: WETH: ", reserve1);
// console.log("Reserve1: USDC: ", reserve0);

// address poolETH_USDT = IUniswapV2Factory(factory).getPair(WETH, USDT);
// (reserve0, reserve1, ) = IUniswapV2Pair(poolETH_USDT).getReserves();
// console.log("Reserve0: USDT: ", reserve1);
// console.log("Reserve1: WETH: ", reserve0);
// uint256 ETH_USDT_amountETHIn = getAmountIn(amountToLiquidate, reserve0, reserve1); //check token0 and 1

// console.log("KK: ", ETH_USDC_amountETHIn);
// console.log("KK: ", ETH_USDT_amountETHIn);



// def g(X):
//     ri = 0
//     ro = 0
//     return (X * rI * 1000) / ((ro - X) * 997) + 1
// def h(X):
//     return X + 5*x/100
