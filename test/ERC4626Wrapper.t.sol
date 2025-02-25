// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/LeagueFactory_TESTNET.sol";
import "../src/League_TESTNET.sol";
import "../src/yieldVaults/ERC4626Wrapper.sol";
import "../src/yieldVaults/MockERC4626.sol";

/**
 * @title ERC4626WrapperTest
 * @notice End-to-end tests that demonstrate the `ERC4626Wrapper` only allows deposit/redeem via a recognized League contract.
 *         The League contract in turn requires the user calling `depositToVault/withdrawFromVault` to have the `TREASURER_ROLE`.
 */
contract ERC4626WrapperTest is Test {
    // Constants for the fork environment
    address public constant USDC = 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B; 
    address public constant whale = 0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F;

    // Test accounts
    address public owner = address(100);          // Owner of the factory
    address public commissioner = address(101);   // Will deploy the league
    address public user1 = address(102);

    LeagueFactory_TESTNET public factory;
    League_TESTNET public league;
    MockERC4626 public mockVault;
    ERC4626Wrapper public wrapper;

    function setUp() public {
        vm.label(owner, "Owner");
        vm.label(commissioner, "Commissioner");
        vm.label(user1, "User1");
        vm.label(whale, "USDC_Whale");

        // Whale has enough ETH for gas
        vm.deal(whale, 10 ether);

        // 1) Deploy factory from "owner"
        vm.startPrank(owner);
        factory = new LeagueFactory_TESTNET();
        vm.stopPrank();

        // 2) Impersonate whale to fund commissioner and user1
        vm.startPrank(whale);
        IERC20(USDC).transfer(commissioner, 5_000 * 1e6);
        IERC20(USDC).transfer(user1, 3_000 * 1e6);
        vm.stopPrank();

        // 3) Commissioner creates a league => 1_000 USDC is put in league
        vm.startPrank(commissioner);
        IERC20(USDC).approve(address(factory), 1_000 * 1e6);
        address leagueAddr = factory.createLeague("TestLeague", 1_000 * 1e6, "CommishTeam");
        vm.stopPrank();
        league = League_TESTNET(leagueAddr);

        // Let's have user1 join the league => another 1_000 USDC inside
        vm.startPrank(user1);
        IERC20(USDC).approve(leagueAddr, 1_000 * 1e6);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // So league now has 2_000 USDC total.

        // 4) Deploy the mock underlying vault
        mockVault = new MockERC4626(IERC20Metadata(USDC));

        // 5) Deploy the ERC4626Wrapper referencing mockVault & factory
        vm.startPrank(owner);
        wrapper = new ERC4626Wrapper(IERC4626(address(mockVault)), address(factory));
        // Add the wrapper to the factory
        factory.addVault(address(wrapper));
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------
    // 1. Test direct calls to wrapper by normal user => revert
    // ----------------------------------------------------------------------
    function testDirectDepositRevert() public {
        // user tries to call wrapper.deposit(1000, user) => "NOT_LEAGUE"
        vm.startPrank(user1);
        vm.expectRevert("NOT_LEAGUE");
        wrapper.deposit(1000, user1);
        vm.stopPrank();
    }

    function testDirectRedeemRevert() public {
        // user tries to redeem => "NOT_LEAGUE"
        vm.startPrank(user1);
        vm.expectRevert("NOT_LEAGUE");
        wrapper.redeem(1000, user1, user1);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------
    // 2. Test deposit via League
    //    The League's `depositToVault(...)` calls wrapper.deposit(...) => success if caller is TREASURER.
    // ----------------------------------------------------------------------
    function testDepositSuccessViaLeague() public {
        // The league has 2000 USDC
        // We impersonate the commissioner, who is also the league's TREASURER by default
        vm.startPrank(commissioner);
        league.depositToVault(address(wrapper), 1_200 * 1e6);
        vm.stopPrank();

        // Now check final balances:
        // The league should have 800 USDC in cashBalance()
        assertEq(league.cashBalance(), 800 * 1e6, "League retains 800 after depositing 1200");

        // The wrapper minted 1200 shares to the league (since league is the receiver in underlying deposit).
        // But to confirm that, let's see what's in the underlying vault:
        // The league contract called wrapper => wrapper did deposit into mockVault => mockVault minted 1200 to the wrapper.
        // We'll check the league's totalVaultBalance() => should be 1200
        uint256 vaultBal = league.totalVaultBalance();
        assertEq(vaultBal, 1_200 * 1e6, "League has 1200 in vaultBalance through the wrapper");
    }

    // ----------------------------------------------------------------------
    // 3. Test deposit revert if the user is not the TREASURER
    // ----------------------------------------------------------------------
    function testDepositRevertNotTreasurer() public {
        // user1 tries to deposit => user1 doesn't have TREASURER_ROLE => revert
        vm.startPrank(user1);
        vm.expectRevert(
            // AccessControl: account ... is missing role ...
        );
        league.depositToVault(address(wrapper), 500 * 1e6);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------
    // 4. Test deposit revert if 0
    // ----------------------------------------------------------------------
    function testDepositRevertZero() public {
        // commissioner calls deposit 0 => revert in wrapper
        vm.startPrank(commissioner);
        vm.expectRevert("Cannot deposit 0");
        league.depositToVault(address(wrapper), 0);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------
    // 5. Test redeem success via League
    // ----------------------------------------------------------------------
    function testRedeemSuccessViaLeague() public {
        // 1) deposit 1000 from the league to the wrapper
        vm.startPrank(commissioner);
        league.depositToVault(address(wrapper), 1_000 * 1e6);
        vm.stopPrank();

        // league now has 1000 left in cash, 1000 in the vault
        assertEq(league.cashBalance(), 1_000 * 1e6);
        assertEq(league.totalVaultBalance(), 1_000 * 1e6);

        // 2) withdraw 400 from the vault
        vm.startPrank(commissioner);
        league.withdrawFromVault(address(wrapper), 400 * 1e6);
        vm.stopPrank();

        // league's cash = 1400, vaultBal=600
        assertEq(league.cashBalance(), 1_400 * 1e6, "league gained 400 from redeem");
        assertEq(league.totalVaultBalance(), 600 * 1e6, "600 left in vault after redemption");
    }

    // ----------------------------------------------------------------------
    // 6. Test redeem revert if user not treasurer
    // ----------------------------------------------------------------------
    function testRedeemRevertNotTreasurer() public {
        // deposit some funds first
        vm.startPrank(commissioner);
        league.depositToVault(address(wrapper), 500 * 1e6);
        vm.stopPrank();

        // user1 tries to withdraw
        vm.startPrank(user1);
        vm.expectRevert(
            // AccessControl: account ... is missing role ...
        );
        league.withdrawFromVault(address(wrapper), 200 * 1e6);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------
    // 7. Test redeem revert if 0
    // ----------------------------------------------------------------------
    function testRedeemRevertZero() public {
        // deposit some
        vm.startPrank(commissioner);
        league.depositToVault(address(wrapper), 500 * 1e6);
        // now try to withdraw 0
        vm.expectRevert("Cannot redeem 0");
        league.withdrawFromVault(address(wrapper), 0);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------------
    // 8. Test unimplemented methods
    // ----------------------------------------------------------------------
    function testWithdrawFunctionReverts() public {
        // The wrapper's `withdraw(uint256, address, address)` is not implemented
        vm.startPrank(address(league));
        vm.expectRevert("Not implemented");
        wrapper.withdraw(10, address(league), address(league));
        vm.stopPrank();
    }

    function testPreviewWithdrawReverts() public {
        vm.expectRevert("Not implemented");
        wrapper.previewWithdraw(10);
    }

    function testMintReverts() public {
        vm.startPrank(address(league));
        vm.expectRevert("Not implemented");
        wrapper.mint(10, address(league));
        vm.stopPrank();
    }

    function testPreviewMintReverts() public {
        vm.expectRevert("Not implemented");
        wrapper.previewMint(10);
    }

    function testMaxWithdrawAlwaysZero() public view {
        // The function in wrapper is coded: `function maxWithdraw(address) public pure returns (uint256) { return 0; }`
        // So let's confirm
        assertEq(wrapper.maxWithdraw(address(league)), 0, "Should be 0 from the wrapper logic");
    }
}
