// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Your contracts
import "../src/yieldVaults/MockERC4626.sol";
import "../src/yieldVaults/ERC4626Wrapper.sol";

/**
 * @title ERC4626WrapperTest
 * @notice Demonstrates testing of the ERC4626Wrapper that wraps a MockERC4626 vault.
 */
contract ERC4626WrapperTest is Test {
    // The "asset" address for the mock vault:
    // We'll treat this as if it's a real token on chain, but in local tests, we just label it.
    address internal constant USDC_ADDRESS = 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B;

    // We'll define test users
    address internal user1;
    address internal user2;

    // The underlying mock vault and the wrapper
    MockERC4626 internal mockVault;
    ERC4626Wrapper internal wrapper;

    /**
     * @dev Runs once before each test.
     *      1. Deploy mock vault referencing asset at 0xa2fc8C40...
     *      2. Deploy wrapper with that mock vault as `underlyingVault`.
     *      3. Mint local "balances" of the asset to user1 and user2 for testing.
     */
    function setUp() public {
        // Label addresses for readability
        user1 = makeAddr("User1");
        user2 = makeAddr("User2");

        // 1. Deploy the mock vault referencing the token at USDC_ADDRESS
        //    Under the hood, the mock vault sees USDC_ADDRESS as an IERC20Metadata
        mockVault = new MockERC4626(IERC20Metadata(USDC_ADDRESS));

        // 2. Deploy the wrapper pointing to the mockVault
        wrapper = new ERC4626Wrapper(mockVault);

        // 3. Give commissioner, user1, user2 some USDC & ETH on a fork
        //    (Here we mock a "usdcHolder" who has enough USDC.)
        //    Adjust these addresses to real whales if needed on a real fork.
        address usdcHolder = address(0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F);
        vm.startPrank(usdcHolder);
        IERC20(USDC_ADDRESS).transfer(user1, 500000e6);
        IERC20(USDC_ADDRESS).transfer(user2, 200000e6);
        vm.stopPrank();

        // Give them some ETH for gas
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
    }

    /**
     * @dev Test depositing into the wrapper, which itself deposits into the mock vault.
     */
    function testDepositAndWithdraw() public {
        // user1 will deposit 100,000 units into the wrapper
        uint256 depositAmount = 100_000e6;

        // user1 approves the wrapper for that deposit
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(wrapper), depositAmount);

        // 1. deposit => wrapper calls underlyingVault.deposit => mints wrapper shares to user1
        uint256 wrapperShares = wrapper.deposit(depositAmount, user1);

        vm.stopPrank();

        // Check that user1 got `wrapperShares` from the wrapper
        assertEq(wrapper.balanceOf(user1), wrapperShares, "User1 wrapper share balance mismatch");

        // The mockVault minted shares to the wrapper. Let's see how many underlying shares the wrapper holds
        uint256 underlyingShares = mockVault.balanceOf(address(wrapper));
        assertEq(underlyingShares, wrapperShares, "Wrapper's underlying vault share mismatch");

        // user1 now wants to withdraw half of the deposit => 50,000
        vm.startPrank(user1);
        // Approve wrapper shares to the wrapper if needed.
        // In your code, if user1 = _owner, no allowance check is needed. We'll just confirm it works
        uint256 sharesWithdrawn = wrapper.withdraw(50_000e6, user1, user1);
        vm.stopPrank();

        // sharesWithdrawn should be ~ the shares that represent 50,000 assets
        // the mock's ratio is basically 1:1 if no other deposits.
        // So sharesWithdrawn ~ 50k if the ratio hasn't changed
        assertEq(sharesWithdrawn, 50_000e6, "Shares withdrawn mismatch");

        // user1's new wrapper share balance => originally had wrapperShares, burned some
        uint256 user1SharesAfter = wrapper.balanceOf(user1);
        assertEq(user1SharesAfter, wrapperShares - sharesWithdrawn, "User1 share balance after partial withdraw mismatch");

        // user1's asset balance should have increased by 50k from the wrapper
        // but we started with 500k, used 100k in deposit => 400k left, then got 50k back => 450k
        // We can check actual final. We'll do a small approximate check:
        uint256 user1FinalAssetBal = IERC20(USDC_ADDRESS).balanceOf(user1);
        // ~ 450k
        assertEq(user1FinalAssetBal, 450_000e6, "User1 final asset balance mismatch after partial withdraw");

        // Also the wrapper's underlying shares should have decreased correspondingly
        uint256 wrapperUnderlyingSharesAfter = mockVault.balanceOf(address(wrapper));
        assertEq(
            wrapperUnderlyingSharesAfter,
            underlyingShares - sharesWithdrawn,
            "Wrapper's vault share after partial withdraw mismatch"
        );
    }

    /**
     * @dev Test minting shares in the wrapper, which calls underlyingVault.mint(...) internally.
     */
    function testMintAndRedeem() public {
        // user2 wants to mint 200_000 "wrapper shares"
        uint256 sharesToMint = 200_000e6;

        vm.startPrank(user2);
        IERC20(USDC_ADDRESS).approve(address(wrapper), type(uint256).max);

        // 1. wrapper.mint => underlyingVault.mint => user2 supplies assets in proportion
        //    The wrapper mints exactly `sharesToMint` to user2
        uint256 assetsSpent = wrapper.mint(sharesToMint, user2);

        vm.stopPrank();

        // user2 should have exactly `sharesToMint` from the wrapper
        assertEq(wrapper.balanceOf(user2), sharesToMint, "User2 wrapper share balance mismatch after mint");

        // The assetsSpent is how many tokens user2 had to supply.
        // Typically 1:1 if the vault is empty initially, so ~ 200k
        uint256 user2FinalAssetBal = IERC20(USDC_ADDRESS).balanceOf(user2);
        // user2 started with 200k, spent assetsSpent
        assertEq(user2FinalAssetBal, 200_000e6 - assetsSpent, "User2 final asset balance mismatch");

        // Now user2 redeems all shares => gets back assets
        vm.startPrank(user2);
        wrapper.redeem(sharesToMint, user2, user2);
        vm.stopPrank();

        // Should burn user2's entire share balance
        assertEq(wrapper.balanceOf(user2), 0, "User2 should have 0 wrapper shares after full redeem");

        // redeemedAssets should match what they spent (minus any ratio changes or zero?),
        // so user2's final asset balance ~ 500k again
        user2FinalAssetBal = IERC20(USDC_ADDRESS).balanceOf(user2);
        assertEq(user2FinalAssetBal, 200_000e6, "User2 final asset balance mismatch after redeem");
    }

    // --------------------------------------------------------------------
    // Edge Cases
    // --------------------------------------------------------------------

    function testZeroDepositReverts() public {
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(wrapper), 0);
        vm.expectRevert(bytes("Cannot deposit 0"));
        wrapper.deposit(0, user1);
        vm.stopPrank();
    }

    function testZeroMintReverts() public {
        vm.startPrank(user1);
        vm.expectRevert(bytes("Cannot mint 0"));
        wrapper.mint(0, user1);
        vm.stopPrank();
    }

    function testZeroWithdrawReverts() public {
        // First user1 deposits something
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(wrapper), 10_000e6);
        wrapper.deposit(10_000e6, user1);
        vm.expectRevert(bytes("Cannot withdraw 0"));
        wrapper.withdraw(0, user1, user1);
        vm.stopPrank();
    }

    function testZeroRedeemReverts() public {
        // user1 mints some shares
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(wrapper), 10_000e6);
        wrapper.mint(5_000e6, user1); // user1 mints 5k shares
        vm.expectRevert(bytes("Cannot redeem 0"));
        wrapper.redeem(0, user1, user1);
        vm.stopPrank();
    }

    // --------------------------------------------------------------------
    // Multiple Users & Ratio Changes
    // --------------------------------------------------------------------

    function testMultipleUsersDepositAndOneWithdraw() public {
        // user1 deposits 100k
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(wrapper), 100_000e6);
        uint256 sharesU1 = wrapper.deposit(100_000e6, user1);
        vm.stopPrank();

        // user2 deposits 200k
        vm.startPrank(user2);
        IERC20(USDC_ADDRESS).approve(address(wrapper), 200_000e6);
        uint256 sharesU2 = wrapper.deposit(200_000e6, user2);
        vm.stopPrank();

        // The ratio might shift if more users join. But in a simple scenario with mock vault 1:1,
        // user1 has "100k shares", user2 has "200k shares".
        assertEq(wrapper.balanceOf(user1), sharesU1, "U1 share mismatch");
        assertEq(wrapper.balanceOf(user2), sharesU2, "U2 share mismatch");
        assertEq(sharesU2, 2 * sharesU1, "Should reflect proportion of deposit if ratio is 1:1 so far");

        // user2 withdraws 100k (half of deposit)
        vm.startPrank(user2);
        uint256 sharesBurned = wrapper.withdraw(100_000e6, user2, user2);
        vm.stopPrank();

        // user2's remaining shares => sharesU2 - sharesBurned
        assertEq(wrapper.balanceOf(user2), sharesU2 - sharesBurned, "User2 share mismatch after partial withdraw");

        // user1's shares or balance is unaffected
        assertEq(wrapper.balanceOf(user1), sharesU1, "User1 share changed unexpectedly");
    }

    // --------------------------------------------------------------------
    // Fuzzing Tests
    // --------------------------------------------------------------------

    /**
     * @dev Foundry "fuzzing" test for deposit.
     *      We randomize depositAmount within a meaningful range [1, 1e12].
     */
    function testFuzzDeposit(uint256 depositAmount) public {
        // Bound depositAmount to a safe range
        // Our user has 500k, so let's keep deposit <= 500k
        depositAmount = bound(depositAmount, 1, 500000e6);

        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(wrapper), depositAmount);

        // We expect no revert
        uint256 shares = wrapper.deposit(depositAmount, user1);
        vm.stopPrank();

        // Check user1's share balance is shares
        assertEq(wrapper.balanceOf(user1), shares, "User1 share mismatch in fuzz deposit");
    }

    /**
     * @dev Fuzzing test for minting shares.
     *      We randomize sharesToMint within a range.
     */
    function testFuzzMint(uint256 sharesToMint) public {
        // We can pick a range for shares [1, 200000e6] for example
        sharesToMint = bound(sharesToMint, 1, 200000e6);

        vm.startPrank(user2);
        // Approve
        IERC20(USDC_ADDRESS).approve(address(wrapper), type(uint256).max);

        // Attempt to mint
        wrapper.mint(sharesToMint, user2);
        vm.stopPrank();

        // user2 share balance => sharesToMint
        assertEq(wrapper.balanceOf(user2), sharesToMint, "User2 minted share mismatch");

        // assetsSpent is how many assets the user provided to get sharesToMint
        // We'll skip advanced ratio checks—just confirm user2's final share is as expected.
    }

    /**
     * @dev Fuzz test partial withdraw after a deposit
     */
    function testFuzzWithdrawAfterDeposit(uint256 depositAmount, uint256 withdrawAmount) public {
        // Bound deposit in [1, 500k]
        depositAmount = bound(depositAmount, 1, 500000e6);
        // Bound withdraw in [0, depositAmount] so we don't revert on "Cannot withdraw 0" or "Insufficient shares"
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(wrapper), depositAmount);
        wrapper.deposit(depositAmount, user1);
        // user1 now tries to withdraw "withdrawAmount"
        // Some amount must be > 0
        uint256 sharesBurned = wrapper.withdraw(withdrawAmount, user1, user1);
        vm.stopPrank();

        // We only check that user1's final share and asset balances are consistent,
        // but we won't do complicated ratio math here.
        // For thoroughness:
        uint256 user1Shares = wrapper.balanceOf(user1);
        // total shares minted so far is ~ deposit => if mock vault is empty initially,
        // ratio is 1:1 => user1 has depositAmount shares
        uint256 expectedSharesAfter = depositAmount - sharesBurned;
        assertEq(user1Shares, expectedSharesAfter, "User1 share mismatch after partial fuzz withdraw");
    }
}
