// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    DeployDSC deployDSC;
    HelperConfig config;
    address ethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    function setUp() external {
        deployDSC = new DeployDSC();
        (dsc, engine, config) = deployDSC.run();
        (ethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = config.activeNetworkConfig();
    }

    ///////////////////////
    // Price tests       //
    ///////////////////////
    function testGetUsdValue() view public {
        uint256 ethAmout = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        assertEq(engine.getUsdValue(weth, ethAmout), 30000e18);
    }
}