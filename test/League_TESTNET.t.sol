// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/LeagueRewardNFT_TESTNET.sol";
import "../src/LeagueFactory_TESTNET.sol";
import "../src/League_TESTNET.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/interfaces/ILeagueRewardNFT.sol";
import "../src/interfaces/IVault.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

// --------------------------------------------
// Minimal ERC4626 Vault
// --------------------------------------------
contract MockVault4626 is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset; // USDC in your test
    address public immutable factory; // Must match factory address

    constructor(IERC20 _asset, address _factory) ERC20("MockVault4626-Token", "mv4626") {
        asset = _asset;
        factory = _factory;
    }

    // IVault interface
    function FACTORY() external view returns (address) {
        return factory;
    }

    // IERC4626 interface
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        // For simplicity, let's do a 1:1 deposit:share ratio
        shares = assets;
        // Pull USDC from caller
        asset.safeTransferFrom(msg.sender, address(this), assets);
        // Mint shares to receiver
        _mint(receiver, shares);
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        // 1:1 ratio
        assets = shares;
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        // 1:1 ratio
        shares = assets;
        // Must have allowance if the caller != owner, but let's not complicate for now
        _burn(owner, shares);
        asset.safeTransfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        // 1:1 ratio
        assets = shares;
        _burn(owner, shares);
        asset.safeTransfer(receiver, assets);
    }

    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares; // 1:1
    }

    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets; // 1:1
    }

    function assetBalance() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    // The rest of the IERC4626 interface:
    function totalAssets() external view returns (uint256) {
        // totalAssets = total supply (1:1)
        return address(this).balance; // or assetBalance() if you want
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        // We don't impose a limit beyond the owner's balance
        return balanceOf(owner);
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }
}

// --------------------------------------------
// The Main Test
// --------------------------------------------
contract LeagueTest is Test {
    // ============ Addresses ============
    LeagueFactory_TESTNET public factory;
    // For convenience:
    address public constant USDC = 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B; // testnet USDC
    address public constant whale = 0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F; // USDC whale on fork

    // Test users
    address public owner = address(10);
    address public commissioner = address(11); // This will create the league
    address public user1 = address(12);
    address public user2 = address(13);

    // Deployed league address
    address public leagueAddr;
    League_TESTNET public league;

    // Mocks
    LeagueRewardNFT_TESTNET public mockNFT;
    MockVault4626 public mockVault;

    // ============ Setup ============
    function setUp() public {
        vm.label(owner, "Owner");
        vm.label(commissioner, "Commissioner");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(whale, "USDC_Whale");
        vm.label(USDC, "USDC");

        // Give the whale some ETH for gas
        vm.deal(whale, 100 ether);

        // Deploy the factory from "owner"
        vm.startPrank(owner);
        factory = new LeagueFactory_TESTNET();
        vm.stopPrank();

        // Deploy the mock reward NFT & verify it references factory
        vm.startPrank(owner);
        mockNFT = new LeagueRewardNFT_TESTNET("League Fund Reward", "LFR", address(factory));
        factory.setLeagueRewardNFT(address(mockNFT));
        vm.stopPrank();

        // Create a mock vault 4626, referencing the same factory
        vm.startPrank(owner);
        mockVault = new MockVault4626(IERC20(USDC), address(factory));
        // Add the vault to the factory
        factory.addVault(address(mockVault));
        vm.stopPrank();

        // Impersonate whale to distribute USDC to test users
        vm.startPrank(whale);
        // Transfer 10k USDC to commissioner
        IERC20(USDC).transfer(commissioner, 10_000 * 1e6);
        // Transfer 5k USDC each to user1 and user2
        IERC20(USDC).transfer(user1, 5_000 * 1e6);
        IERC20(USDC).transfer(user2, 5_000 * 1e6);
        vm.stopPrank();

        // Now, commissioner creates a league through the factory
        vm.startPrank(commissioner);
        IERC20(USDC).approve(address(factory), 2_000 * 1e6);
        // Pass 1,000 USDC as "dues"
        leagueAddr = factory.createLeague("TestLeague", 1_000 * 1e6, "CommissionerTeam");
        vm.stopPrank();

        league = League_TESTNET(leagueAddr);
    }

    // ============ Tests ============

    // 1. Test initial league state
    function testInitialLeagueState() public view {
        // The league should be recognized by the factory
        assertTrue(factory.isLeague(address(league)), "League is recognized by factory");

        // The name matches "TestLeague"
        assertEq(league.name(), "TestLeague", "League name should match");
        // The commissioner has COMMISSIONER_ROLE & TREASURER_ROLE
        bytes32 COMMISSIONER_ROLE = league.COMMISSIONER_ROLE();
        bytes32 TREASURER_ROLE = league.TREASURER_ROLE();
        assertTrue(league.hasRole(COMMISSIONER_ROLE, commissioner), "Commissioner should have COMMISSIONER_ROLE");
        assertTrue(league.hasRole(TREASURER_ROLE, commissioner), "Commissioner should have TREASURER_ROLE");

        // The first season is created in the constructor
        League_TESTNET.SeasonData memory firstSeason = league.currentSeason();
        assertEq(firstSeason.dues, 1_000 * 1e6, "Initial season dues is 1000 USDC");
        assertEq(firstSeason.teams.length, 1, "Should have exactly 1 team in the first season (the commissioner)");
        assertEq(firstSeason.teams[0], commissioner, "Commissioner is the only team in the first season");
    }

    // 2. Test createSeason
    function testCreateSeason() public {
        // Current league has 1 season. Let's create a second one
        vm.startPrank(commissioner);
        IERC20(USDC).approve(address(league), 2_000 * 1e6);
        league.createSeason(2_000 * 1e6);
        vm.stopPrank();

        // Check season count: 2
        // seasons[0], seasons[1]
        // The newly created season has dues=2000, and automatically the commissioner joined.
        League_TESTNET.SeasonData memory newSeason = league.currentSeason();
        assertEq(newSeason.dues, 2_000 * 1e6, "Second season dues = 2000");
        assertEq(newSeason.teams.length, 1, "Commissioner auto-joined the new season");
        assertEq(newSeason.teams[0], commissioner, "Commissioner is first in the second season");
    }

    // 3. Test createSeason revert if non-commissioner calls
    function testCreateSeasonRevertNotCommissioner() public {
        vm.startPrank(user1);
        vm.expectRevert(
            // AccessControl revert string: "AccessControl: account ... is missing role ..."
        );
        league.createSeason(1_000 * 1e6);
        vm.stopPrank();
    }

    // 4. Test createSeason revert if dues < seasonCreationFee
    function testCreateSeasonRevertDuesTooLow() public {
        // Suppose the factory owner sets a season creation fee of 1500 USDC
        vm.startPrank(owner);
        factory.setSeasonCreationFee(1500 * 1e6);
        vm.stopPrank();

        // Commissioner tries to create a new season with only 1000 USDC
        vm.startPrank(commissioner);
        vm.expectRevert("DUES_TOO_LOW");
        league.createSeason(1_000 * 1e6);
        vm.stopPrank();
    }

    // 5. Test joinSeason
    function testJoinSeason() public {
        // The current (first) season has dues=1000. user1 wants to join.
        // user1 must pay 1000 USDC to the league.
        vm.startPrank(user1);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // Verify user1 is in the current season
        League_TESTNET.SeasonData memory season = league.currentSeason();
        assertEq(season.teams.length, 2, "Now two teams in the first season");
        assertEq(season.teams[1], user1, "User1 is second team in the season");

        // user2 can also join
        vm.startPrank(user2);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        league.joinSeason("User2Team");
        vm.stopPrank();

        season = league.currentSeason();
        assertEq(season.teams.length, 3, "Now three teams (commissioner, user1, user2)");
        assertEq(season.teams[2], user2, "User2 is third team");
    }

    // 6. Test joinSeason revert if already joined
    function testJoinSeasonRevertTeamAlreadyJoined() public {
        // The commissioner is already in the first season, so calling joinSeason again with commissioner
        // should revert "TEAM_ALREADY_JOINED".
        vm.startPrank(commissioner);
        vm.expectRevert("TEAM_ALREADY_JOINED");
        league.joinSeason("CommissionerTeam");
        vm.stopPrank();
    }

    // 7. Test joinSeason revert if the name is mismatched for an existing wallet
    function testJoinSeasonRevertTeamNameMismatch() public {
        // user1 joins as "User1Team"
        vm.startPrank(user1);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // If user1 tries to join a new season (or the same) with a different name, it reverts
        // But let's do it on the same season for demonstration
        vm.startPrank(user1);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        vm.expectRevert("TEAM_ALREADY_JOINED");
        league.joinSeason("DifferentName");
        vm.stopPrank();
    }

    // 8. Test removeTeam
    function testRemoveTeam() public {
        // user1 joins the first season
        vm.startPrank(user1);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        league.joinSeason("User1Team");
        vm.stopPrank();

        League_TESTNET.SeasonData memory season = league.currentSeason();
        assertEq(season.teams.length, 2, "Two teams: commissioner, user1");

        // Commissioner removes user1 from the season
        vm.startPrank(commissioner);
        league.removeTeam(user1);
        vm.stopPrank();

        // Now user1 should not be active in the current season
        season = league.currentSeason();
        assertEq(season.teams.length, 1, "Only commissioner remains in the season");
        assertEq(season.teams[0], commissioner, "Remaining is commissioner");
        assertFalse(league.isTeamActive(user1), "User1 is no longer active");
        // user1 got refunded 1000 USDC
        assertEq(IERC20(USDC).balanceOf(user1), 5_000 * 1e6, "User1 was refunded the 1000 USDC they paid");
    }

    // 9. Test removeTeam revert if not commissioner
    function testRemoveTeamRevertNotCommissioner() public {
        // user1 is in the league already
        vm.startPrank(user1);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // user1 tries to remove themselves => revert
        vm.startPrank(user1);
        vm.expectRevert(
            // AccessControl revert
        );
        league.removeTeam(user2);
        vm.stopPrank();
    }

    // 10. Test removeTeam revert if team not in season
    function testRemoveTeamRevertTeamNotInSeason() public {
        // user1 never joined, so removing them should revert
        vm.startPrank(commissioner);
        vm.expectRevert("TEAM_NOT_IN_SEASON");
        league.removeTeam(user1);
        vm.stopPrank();
    }

    // 11. Test setCommissioner
    function testSetCommissioner() public {
        // Commissioner changes to user1
        vm.startPrank(commissioner);
        league.setCommissioner(user1);
        vm.stopPrank();

        // Now user1 has commissioner role, old commissioner lost it
        bytes32 COMMISSIONER_ROLE = league.COMMISSIONER_ROLE();
        assertTrue(league.hasRole(COMMISSIONER_ROLE, user1), "User1 is new commissioner");
        assertFalse(league.hasRole(COMMISSIONER_ROLE, commissioner), "Old commissioner lost role");
    }

    // 12. Test addTreasurer / removeTreasurer
    function testTreasurerFunctions() public {
        bytes32 TREASURER_ROLE = league.TREASURER_ROLE();

        // Commissioner adds user1 as treasurer
        vm.startPrank(commissioner);
        league.addTreasurer(user1);
        vm.stopPrank();

        // user1 has treasurer role
        assertTrue(league.hasRole(TREASURER_ROLE, user1), "User1 is a treasurer now");

        // Then commissioner removes user1 from treasurer
        vm.startPrank(commissioner);
        league.removeTreasurer(user1);
        vm.stopPrank();
        assertFalse(league.hasRole(TREASURER_ROLE, user1), "User1 is no longer a treasurer");
    }

    // 13. Test allocateReward
    function testAllocateReward() public {
        // user1 joins so we can allocate a reward
        vm.startPrank(user1);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // Commissioner allocates a 100 USDC reward
        vm.startPrank(commissioner);
        league.allocateReward(user1, "BestTeam", 100 * 1e6);
        vm.stopPrank();

        // Check that totalClaimableRewards = 100 USDC
        assertEq(league.totalClaimableRewards(), 100 * 1e6, "totalClaimableRewards should be 100 USDC");
    }

    // 14. Test allocateReward revert if team not in season
    function testAllocateRewardRevertTeamNotInSeason() public {
        vm.startPrank(commissioner);
        vm.expectRevert("TEAM_NOT_IN_SEASON");
        league.allocateReward(user1, "NonExistentTeam", 100 * 1e6);
        vm.stopPrank();
    }

    // 15. Test allocateReward revert if insufficient cash balance
    function testAllocateRewardRevertInsufficientCashBalance() public {
        // user1 joins, paying 1000 USDC
        vm.startPrank(user1);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // The league has exactly 2000 USDC from user1's and commissioners dues.
        // We try to allocate 2500 USDC to user1
        vm.startPrank(commissioner);
        vm.expectRevert("INSUFFICIENT_CASH_BALANCE");
        league.allocateReward(user1, "BigReward", 2500 * 1e6);
        vm.stopPrank();
    }

    // 16. Test claimReward
    function testClaimReward() public {
        // user1 joins
        vm.startPrank(user1);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // commissioner allocates 200 USDC reward
        vm.startPrank(commissioner);
        league.allocateReward(user1, "RegularSeasonChamp", 200 * 1e6);
        vm.stopPrank();

        // user1 claims reward. This also calls mintReward on the NFT,
        // then transfers 200 USDC from league to user1
        string[] memory imageURLs = new string[](1);
        imageURLs[0] = "ipfs://someImageHash";

        // user1's USDC before claim = 4k left in their wallet (they spent 1k to join)
        // Actually 5k - 1k = 4k
        uint256 beforeBalance = IERC20(USDC).balanceOf(user1);

        vm.startPrank(user1);
        league.claimReward(imageURLs);
        vm.stopPrank();

        // user1's USDC after claim should be beforeBalance + 200
        uint256 afterBalance = IERC20(USDC).balanceOf(user1);
        assertEq(afterBalance, beforeBalance + 200 * 1e6, "User1 gained 200 USDC from reward");
        // totalClaimableRewards = 0
        assertEq(league.totalClaimableRewards(), 0, "All rewards claimed");
    }

    // 17. Test depositToVault
    function testDepositToVault() public {
        // By default, the commissioner is also the treasurer, so they can deposit
        // Suppose we want to deposit some leftover from the league's balance.

        // Right now, the league has 1000 USDC from the commissioner’s initial creation.
        // Let's have user1 join so the league has 2k total (1000 from commissioner + 1000 from user1).
        vm.startPrank(user1);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // Let's deposit 1,500 USDC into the vault, leaving some buffer for claimableRewards=0 anyway
        vm.startPrank(commissioner);
        league.depositToVault(address(mockVault), 1_500 * 1e6);
        vm.stopPrank();

        // Now check that the vault minted 1,500 shares to the league,
        // and the league's USDC is decreased by 1,500.
        assertEq(mockVault.balanceOf(address(league)), 1_500 * 1e6, "League holds 1500 vault shares");
        uint256 leagueCash = league.cashBalance();
        // Commissioner had 1000 from creation, user1 joined with 1000 => total 2000 USDC
        // We deposited 1500 into the vault => left 500 in league cash
        assertEq(leagueCash, 500 * 1e6, "500 USDC left in league cash");
    }

    // 18. Test depositToVault revert if not treasurer
    function testDepositToVaultRevertNotTreasurer() public {
        vm.startPrank(user1);
        vm.expectRevert(
            // "AccessControl: account ... is missing role TREASURER_ROLE"
        );
        league.depositToVault(address(mockVault), 1000 * 1e6);
        vm.stopPrank();
    }

    // 19. Test depositToVault revert if vault not recognized
    function testDepositToVaultRevertNotVault() public {
        // Create a random address or mock that isn't added to the factory
        MockVault4626 unlistedVault = new MockVault4626(IERC20(USDC), address(0x1234));

        vm.startPrank(commissioner);
        vm.expectRevert("NOT_VAULT");
        league.depositToVault(address(unlistedVault), 1000 * 1e6);
        vm.stopPrank();
    }

    // 20. Test depositToVault revert if insufficient cash (beyond totalClaimableRewards)
    function testDepositToVaultRevertInsufficientBalance() public {
        // The league has 2000 USDC from commissioner and user1.
        // Let's allocate a 1000 USDC reward to user1, so totalClaimableRewards=1000
        // That means we can only deposit 1000 safely
        vm.startPrank(user1);
        IERC20(USDC).approve(address(league), 1_000 * 1e6);
        league.joinSeason("User1Team");
        vm.stopPrank();

        vm.startPrank(commissioner);
        league.allocateReward(user1, "HoldThis", 1_000 * 1e6);

        // Try depositing 500 => revert
        vm.expectRevert("INSUFFICIENT_CASH_BALANCE");
        league.depositToVault(address(mockVault), 1_500 * 1e6);
        vm.stopPrank();
    }

    // 21. Test withdrawFromVault
    function testWithdrawFromVault() public {
        // First deposit some to the vault
        vm.startPrank(commissioner);
        league.depositToVault(address(mockVault), 1_000 * 1e6);
        vm.stopPrank();

        // The league has 1,000 shares in the vault
        // We want to redeem 400 shares
        vm.startPrank(commissioner);
        league.withdrawFromVault(address(mockVault), 400 * 1e6);
        vm.stopPrank();

        // The league's share balance in mockVault should be 600 now
        assertEq(mockVault.balanceOf(address(league)), 600 * 1e6, "League left with 600 shares");
        // The league's USDC increased by 400
        assertEq(league.cashBalance(), 400 * 1e6, "League has 400 USDC withdrawn");
    }

    // 22. Test withdrawFromVault revert if not treasurer
    function testWithdrawFromVaultRevertNotTreasurer() public {
        vm.startPrank(user1);
        vm.expectRevert(
            // AccessControl revert
        );
        league.withdrawFromVault(address(mockVault), 100 * 1e6);
        vm.stopPrank();
    }

    // 23. Test withdrawFromVault revert if insufficient vault balance
    function testWithdrawFromVaultRevertInsufficientVaultBalance() public {
        // deposit 300
        vm.startPrank(commissioner);
        league.depositToVault(address(mockVault), 300 * 1e6);
        // trying to withdraw 400 => revert
        vm.expectRevert("INSUFFICIENT_VAULT_BALANCE");
        league.withdrawFromVault(address(mockVault), 400 * 1e6);
        vm.stopPrank();
    }

    // 24. Test closeLeague
    function testCloseLeague() public {
        // The league currently has 1000 USDC from commissioner
        // If we had multiple seasons, that wouldn't matter, closeLeague empties everything
        // and calls factory.removeLeague()

        // Commissioner calls closeLeague
        vm.startPrank(commissioner);
        league.closeLeague();
        vm.stopPrank();

        // The league is no longer recognized
        assertFalse(factory.isLeague(address(league)), "League is removed from factory");
        // The league's USDC balance is now 0
        assertEq(league.cashBalance(), 0, "League has no more USDC");
        // The commissioner got the final balance
        assertEq(IERC20(USDC).balanceOf(commissioner), 10_000 * 1e6, "Commissioner reclaimed league's balance");
        // Because they started with 10k, used 1k for creation, the league eventually gave it all back on close
    }

    // 25. Test closeLeague revert if not commissioner
    function testCloseLeagueRevertNotCommissioner() public {
        vm.startPrank(user1);
        vm.expectRevert(
            // AccessControl revert
        );
        league.closeLeague();
        vm.stopPrank();
    }
}
