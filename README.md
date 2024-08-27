# defi-mooc-lab2

## Current Best

`Profit = 92.107607968317628576 ETH`

## Crux of the Problem

There are specifically two problems to solve in order to maximize profit:

**P1:** Identifying pools with high liquidity, which leads to lower slippage. The challenge here is that historical data is difficult to obtain.

**P2:** Determining the exact amount to liquidate for maximum profit.

For **P1**, I searched through Dune Analytics and made a few educated guesses based on one-year-old data from [Uniswap](https://app.uniswap.org/explore/pools/ethereum/0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852). The final decision was made by comparing (reserve0, reserve1) of different pools after pre-selection.
Some ideas that didn’t work for **P1**:
1. Directly using the WBTC/USDT pool (Liquidity was too low)
2. Using WETH/USDC and then USDC/USDT pools to get USDT instead of WETH/USDT. Although WETH/USDC has more liquidity, the overall cost was higher.

For **P2**, if the user’s debt is X and the health factor is less than 1, then the maximum liquidation amount = X / 2. I performed a binary search starting between 0 and X/2, and after a few trials, I determined the optimal liquidation amount to be 1723415014000 which yielded the highest profit I could achieve locally.

#### Solution Flow
1. Take a flash loan from the WETH/USDT pool.
2. In the callback:
  * Use the USDT to liquidate the user.
  * Receive WBTC as a reward for the liquidation.
  * Swap all the WBTC to WETH in the WETH/WBTC pool.
  * Repay the flash loan with WETH.
3. Transfer the remaining WETH as ETH to the liquidator.

## Potential Improvements:

1. Conducting a more thorough search for pools with even higher liquidity.
2. Splitting a large swap into two smaller swaps to reduce slippage.
3. Querying all necessary data (liquidation bonus, price, etc.) to calculate the collateral given to the liquidator after a successful liquidation, and using that function `F(debtToCover)` in combination with swap slippage calculations to determine the exact liquidation amount that maximizes profit.