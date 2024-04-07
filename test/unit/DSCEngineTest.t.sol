// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    DeployDSC deployDSC;
    HelperConfig config;
    address ethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public AMOUNT_COLLATERAL = 10 ether;
    uint256 public STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        deployDSC = new DeployDSC();
        (dsc, engine, config) = deployDSC.run();
        (ethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // Price tests       //
    ///////////////////////
    function testGetUsdValue() view public {
        uint256 ethAmout = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        assertEq(engine.getUsdValue(weth, ethAmout), 30000e18);
    }

    //////////////////////////////////
    // depositColateral tests       //
    //////////////////////////////////
    function testRevertIfCollateralZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
    }
}