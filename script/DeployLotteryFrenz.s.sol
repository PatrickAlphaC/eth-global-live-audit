// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {Script} from "forge-std/Script.sol";
import {LotteryFrenz} from "../src/LotteryFrenz.sol";

contract DeployLotteryFrenz is Script {
    uint256 entranceFee = 1e18;
    uint256 duration = 1 days;

    address constant MAINNET_UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function run() public returns (LotteryFrenz) {
        vm.broadcast();
        LotteryFrenz lotteryFrenz = new LotteryFrenz(
            1e18,
            duration,
            MAINNET_USDC,
            MAINNET_UNISWAP_V2_ROUTER,
            MAINNET_WETH
        );
        return lotteryFrenz;
    }
}
