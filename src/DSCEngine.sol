// SPDX-License-Identifier: MIT

// Layout of Contract: 
// version
// imports
// errors
// interfaces, libraries, contracts
// type declarations
// state variables
// events
// modifiers
// functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external 
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title DSCEngine
 * @author Vinicius Assis
 * 
 * The systemm is designed to be as minimal as possible, and have the tokens maintain a 1 token = $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral (ETH & BTC)
 * - Dollar Pegged
 * - Algorithmic Stable
 * 
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 * 
 * Out DSC system should alway be "overcollaterized". At no point, should the value of all collateral <=the $ backed value of all the DSC.
 * 
 * @notice This contract is the core of the DSC System. It habdles all the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    //////////////
    // Errors   //
    //////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedsMustHaveSameLength();
    error DSCEngine__TokenNotSupported();
    /////////////////////
    // State Variables //
    /////////////////////
    mapping(address tokens => address priceFeed) private s_priceFeeds; //tokenToPriceFeeds

    DecentralizedStableCoin private i_dsc;

    /////////////////
    // Modifiers   //
    /////////////////
    modifier moreThanZero(uint256 _amount){
        if(_amount <= 0){
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DSCEngine__TokenNotSupported();
        }
        _;
    }

    /////////////////
    // Functions   //
    /////////////////
    constructor(
        address[] memory tokenAddresses, 
        address[] memory priceFeeds,
        address dscAddress
    ) {
        // USD Price Feeds
        if(tokenAddresses.length != priceFeeds.length){
            revert DSCEngine__TokenAddressesAndPriceFeedsMustHaveSameLength();
        }
        // For example ETH/USD, BTC/USD, etc.
        for(uint256 i = 0; i < tokenAddresses.length; i++){
            s_priceFeeds[tokenAddresses[i]] = priceFeeds[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////
    function depositCollateralAndMintDsc() external {}

    /**
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of the token to deposit as collateral
    */ 
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant{}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {} 

    function getHealthFactor() external view returns(uint256) {}

}