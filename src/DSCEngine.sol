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

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();
    /////////////////////
    // State Variables //
    /////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus for liquidating

    mapping(address tokens => address priceFeed) private s_priceFeeds; //tokenToPriceFeeds
    mapping(address user => mapping(address token => uint256 amount)) private s_colateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private i_dsc;

    //////////////////
    // Events       //
    //////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);

    /////////////////
    // Modifiers   //
    /////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
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
    constructor(address[] memory tokenAddresses, address[] memory priceFeeds, address dscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeeds.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsMustHaveSameLength();
        }
        // For example ETH/USD, BTC/USD, etc.
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeeds[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////

    /**
     * 
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of the token to deposit as collateral
     * @param amoutDscToMint The amount of DSC to mint
     * @notice this function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amoutDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amoutDscToMint);
    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of the token to deposit as collateral
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_colateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * 
     * @param tokenCollateralAddress The address of the token to redeem as collateral
     * @param amountCollateral The amount of the token to redeem as collateral
     * @param amountToBurn The amount of DSC to burn
     * @notice this function burns DSC and redeems underlying collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToBurn) external {
        burnDsc(amountToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeem collateral already checks health factor

    }

    // in order to redeem collateral:
    // 1. health factor must be over 1 AFTER collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of DSC to mint
     * @notice they must have more collateral value than the minumum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if they minted too much ($150 DSC, 100 $ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount){
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I dont think this would ever hit
    }

    // If we do start nearing undercollateralization, we need someone to liquidate positions

    // $100 ETH backing $50 DSC
    // $20 ETH backing $50 DSC <- DSC isnt worth $1!!

    // $75 ETH backing $50 DSC
    // Liquidator take $75 ETH backing and burns off the $50 DSC

    // if someone is almost undercollateralized, we will pay you to liquidate them!

    /**
     * @param collateral The erc20 collateral address to liquidate
     * @param user The user who has broken the health factor. Their _healthFactos should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the health factor
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking user funds
     * @notice This function working assumes the protocol will be 100% overcollateralized in order for this to work
     * @notice a known bug would be if the protocol were 100% or less collateralized, then we wouldnt be able to incentivize the liquidators. 
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        // Bad user: $140 ETH backing $100 DSC
        // debtToCover = $100
        // $100 DSC == ??
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor < startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
    }

    function getHealthFactor() external view returns (uint256) {}

    ///////////////////////////////////////
    // Private & Internal View Functions //
    ///////////////////////////////////////

    /**
     * @dev low level internal function, do not call unless the function calling it is checking for health factors being broken
     * @param amountDscToBurn The amount of DSC to burn
     * @param onBehalfOf The user who is burning the DSC
     * @param dscFrom The address of the DSC to burn from
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
        s_colateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
    /**
     * Returns how close to liquidation a user is.
     * If a user goes below 1, then they can get liquidated
     * @param user The address of the user to check the health factor of
     */

    function _healthFactor(address user) private view returns (uint256) {
        // 1. total DSC minted
        // 2. total collateral VALUE
        (uint256 totalDscMinted, uint256 collateralValue) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // $150 ETH / 100 DSC = 1.5
        // 150 * 50 = 7500 / 100 = (75 / 100) < 10

        // $1000 ETH / 100 DSC
        // 1000 * 50 = 50000 / 100 = (500 / 100) > 1
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    // 1. Check health factor (do they have enough collateral?)
    // 2. If not, revert
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ///////////////////////////////////////
    // Public & External View Functions  //
    ///////////////////////////////////////
    function getTokenAmountFromUsd(address token, uint256 amountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // (10e18 * 1e18) / (2000e8 * 1e10) = 500e18
        return ((amountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_colateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // The returned value from CL will be 1000 * 10^8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
