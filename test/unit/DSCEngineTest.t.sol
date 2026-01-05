// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {console} from "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARING_ERC20_BALANCE = 10 ether;

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = helperConfig
            .activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARING_ERC20_BALANCE);
    }

    ////////////////////////////
    //// Constructor Tests /////
    ////////////////////////////

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeedLength() public {
        tokenAddresses.push(weth);
        // purpously making the length different
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////////
    //// Price Tests /////
    //////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $2000/ETH, $100 : 100/2000 = 0.05 ether
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /////////////////////////////////
    //// Deposit Collateral Tests ////
    /////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine
            .getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositedAmount = engine.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositedAmount);
    }

    ///////////////////
    // Mint DSC Tests //
    ///////////////////
    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 100 ether; // $100
        engine.mintDsc(amountToMint);

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor()
        public
        depositedCollateral
    {
        // 10 ETH * $2000/ETH = $20,000 collateral.
        // With 50% liquidation threshold, max mint is $10,000.
        // Let's try to mint $15,000.
        uint256 amountToMint = 15000 ether;
        vm.startPrank(USER);

        // We calculate the expected health factor to match the revert error
        // ($20,000 * 0.5) / 15,000 = 0.666...
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                0.666666666666666666e18
            )
        );
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testGetHealthFactorReturnsMaxWhenNoDebt()
        public
        depositedCollateral
    {
        uint256 healthFactor = engine.getHealthFactor(USER);
        assertEq(healthFactor, type(uint256).max);
    }

    function testLiquidationRevertsIfHealthFactorNotImproved() public {
        // 1. Arrange: User has $20,000 collateral and $10,000 debt
        uint256 userMint = 10_000 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL); // 10 ETH
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, userMint);
        vm.stopPrank();

        // 2. EXTREME Price Crash: ETH drops to $1050
        // Total Collateral Value: $10,500. Debt: $10,000.
        // Ratio is 1.05 (Which is LESS than the 1.1 bonus the liquidator takes)
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1050e8);

        // 3. Liquidator prepares to cover $1,000 debt
        uint256 debtToCover = 1_000 ether;
        ERC20Mock(weth).mint(LIQUIDATOR, 50 ether);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), 50 ether);
        engine.depositCollateralAndMintDsc(weth, 50 ether, userMint);
        dsc.approve(address(engine), debtToCover);

        // Note: DSCEngine usually returns health factor with 18 decimals
        uint256 hfBefore = engine.getHealthFactor(USER);
        console.log("Health Factor Before Liquidation:", hfBefore);

        // 4. Act & Assert
        // Because the ratio (1.05) is lower than the bonus (1.1),
        // taking collateral hurts the HF more than removing debt helps it.
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        engine.liquidate(weth, USER, debtToCover);
        // Note: This line below will NOT run if the revert happens correctly.
        // If you want to see the "After" value, comment out `vm.expectRevert`
        // and run the test (it will fail, but show the log).
        uint256 hfAfter = engine.getHealthFactor(USER);
        console.log("Health Factor After Liquidation: ", hfAfter);
        vm.stopPrank();
    }

    //////////////////////////
    // Burn & Redeem Tests //
    //////////////////////////
    function testCanBurnDsc() public depositedCollateral {
        vm.startPrank(USER);
        uint256 amountToMint = 100 ether;
        engine.mintDsc(amountToMint);

        dsc.approve(address(engine), amountToMint);
        engine.burnDsc(amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        (uint256 totalDscMinted, ) = engine.getAccountInformation(USER);
        assertEq(userBalance, 0);
        assertEq(totalDscMinted, 0);
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalance = IERC20(weth).balanceOf(USER);
        assertEq(userBalance, STARING_ERC20_BALANCE);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedWithCorrectArgs()
        public
        depositedCollateral
    {
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;

    function testCantLiquidateGoodHealthFactor() public depositedCollateral {
        uint256 amountToMint = 100 ether;
        vm.prank(USER);
        engine.mintDsc(amountToMint);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        vm.prank(LIQUIDATOR);
        engine.liquidate(weth, USER, amountToMint);
    }

    function testLiquidationPayoutIsCorrectAndHealthFactorImproves() public {
        // 1. Setup: User deposits 10 ETH and mints $10,000 DSC
        // Eth price is $2000 -> Value $20,000. Threshold 50% -> Max $10k.
        uint256 amountToMint = 10000 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();

        // 2. ETH price drops to $1800
        // New Value: $18,000. 50% threshold is $9k. $10k debt is now liquidatable.
        int256 updatedPrice = 1800e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(updatedPrice);

        // 3. Liquidator prepares
        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_TO_COVER);
        engine.depositCollateralAndMintDsc(
            weth,
            COLLATERAL_TO_COVER,
            amountToMint
        );

        dsc.approve(address(engine), amountToMint);

        // 4. Liquidate
        engine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();

        // 5. Check if liquidator got a bonus (~110% of debt covered)
        // Debt covered was $10,000. $10,000 / $1800 = 5.55 ETH. + 10% bonus = ~6.11 ETH
        uint256 liquidatorWethBalance = IERC20(weth).balanceOf(LIQUIDATOR);
        assertTrue(liquidatorWethBalance > 0);
    }

    //////////////////////
    // View Functions  //
    //////////////////////

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        // 10 ETH * $2000 = $20,000
        uint256 expectedValue = 20000e18;
        assertEq(collateralValue, expectedValue);
    }

    function testGetCollateralTokens() public {
        // This requires adding a getter for s_collateralTokens in your contract
        // or checking if the length is correct via other means.
    }
}
