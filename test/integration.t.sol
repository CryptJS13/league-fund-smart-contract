// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

// Contracts/interfaces (adjust paths as necessary)
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/LeagueFactory_TESTNET.sol";
import "../src/LeagueRewardNFT_TESTNET.sol";
import "../src/yieldVaults/MockERC4626.sol";
import "../src/yieldVaults/ERC4626Wrapper.sol";
import "../src/League_TESTNET.sol";
import "../src/interfaces/ILeagueFactory.sol";
import "../src/interfaces/ILeagueRewardNFT.sol";

/**
 * @title FullIntegrationTest
 * @notice A test suite that covers end-to-end functionality among:
 *         - LeagueFactory_TESTNET
 *         - LeagueRewardNFT_TESTNET
 *         - MockERC4626 & ERC4626Wrapper
 *         - League_TESTNET
 *         * On a forked Sepolia network using USDC at 0xa2fc8C407...
 */
contract FullIntegrationTest is Test {
    // Sepolia addresses and fork block
    address internal constant SEPOLIA_USDC = 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B;
    address internal constant USDC_WHALE = 0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F;

    // Contract references
    LeagueFactory_TESTNET factory;
    LeagueRewardNFT_TESTNET rewardNft;
    MockERC4626 mockVault;
    ERC4626Wrapper wrapper;

    // We'll store league addresses after creation
    address league1;
    address league2;

    // Addresses for commissioners, users, treasurers
    address commissioner1;
    address commissioner2;
    address user1;
    address user2;
    address user3;
    address treasurer1;
    address treasurer2;

    /**
     * @dev setUp() runs before each test. We:
     *      1) Fork Sepolia
     *      2) Deploy Factory, RewardNFT, MockERC4626, Wrapper
     *      3) Create & label addresses, fund them with USDC from the whale
     */
    function setUp() public {
        // 1. Deploy factory & reward NFT
        factory = new LeagueFactory_TESTNET();
        rewardNft = new LeagueRewardNFT_TESTNET("RewardNFT", "RWD", address(factory));
        // set reward NFT
        vm.prank(factory.owner());
        factory.setLeagueRewardNFT(address(rewardNft));

        // Deploy mock vault & wrapper
        mockVault = new MockERC4626(IERC20Metadata(SEPOLIA_USDC));
        wrapper = new ERC4626Wrapper(IERC4626(address(mockVault)), address(factory));
        factory.addVault(address(wrapper));

        // 2. Addresses
        commissioner1 = makeAddr("Commissioner1");
        commissioner2 = makeAddr("Commissioner2");
        user1 = makeAddr("User1");
        user2 = makeAddr("User2");
        user3 = makeAddr("User3");
        treasurer1 = makeAddr("Treasurer1");
        treasurer2 = makeAddr("Treasurer2");

        vm.deal(commissioner1, 1 ether);
        vm.deal(commissioner2, 1 ether);
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);
        vm.deal(user3, 1 ether);
        vm.deal(treasurer1, 1 ether);
        vm.deal(treasurer2, 1 ether);

        // 3. Impersonate USDC whale & distribute
        vm.startPrank(USDC_WHALE);
        IERC20(SEPOLIA_USDC).transfer(commissioner1, 100_000e6);
        IERC20(SEPOLIA_USDC).transfer(commissioner2, 100_000e6);
        IERC20(SEPOLIA_USDC).transfer(user1, 50_000e6);
        IERC20(SEPOLIA_USDC).transfer(user2, 50_000e6);
        IERC20(SEPOLIA_USDC).transfer(user3, 50_000e6);
        IERC20(SEPOLIA_USDC).transfer(treasurer1, 50_000e6);
        IERC20(SEPOLIA_USDC).transfer(treasurer2, 50_000e6);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------
    // Test factory setSeasonCreationFee & revert if dues < fee
    // ----------------------------------------------------------------
    function testFactorySeasonCreationFee() public {
        // By default, it's 0. We'll set it to 5k
        vm.prank(factory.owner());
        factory.setSeasonCreationFee(5_000e6);

        // Commissioner1 tries to create league with 2k => revert
        vm.startPrank(commissioner1);
        IERC20(SEPOLIA_USDC).approve(address(factory), 2000e6);
        vm.expectRevert(bytes("DUES_TOO_LOW"));
        factory.createLeague("FeeLeague", 2000e6, "CommishTeam");
        vm.stopPrank();

        // Now with 10k => success
        vm.startPrank(commissioner1);
        IERC20(SEPOLIA_USDC).approve(address(factory), 10_000e6);
        address feeLeague = factory.createLeague("FeeLeague", 10_000e6, "CommishTeam");
        vm.stopPrank();
        assertTrue(feeLeague != address(0), "FeeLeague is zero address");
    }

    // ----------------------------------------------------------------
    // Test: Commissioners create leagues, multiple joins, check revert scenarios
    // ----------------------------------------------------------------
    function testCreateLeaguesAndJoins() public {
        // Commissioner1 => create league1
        vm.startPrank(commissioner1);
        IERC20(SEPOLIA_USDC).approve(address(factory), 10_000e6);
        league1 = factory.createLeague("LeagueOne", 10_000e6, "CommishTeam1");
        vm.stopPrank();

        // Commissioner2 => create league2
        vm.startPrank(commissioner2);
        IERC20(SEPOLIA_USDC).approve(address(factory), 20_000e6);
        league2 = factory.createLeague("LeagueTwo", 20_000e6, "CommishTeam2");
        vm.stopPrank();

        // user1 => tries to join league1 without approving enough => revert
        vm.startPrank(user1);
        IERC20(SEPOLIA_USDC).approve(league1, 1_000e6);
        vm.expectRevert(); // not enough to pay 10k
        League_TESTNET(league1).joinSeason("User1L1");
        vm.stopPrank();

        // user1 => fix approval
        vm.startPrank(user1);
        IERC20(SEPOLIA_USDC).approve(league1, 10_000e6);
        League_TESTNET(league1).joinSeason("User1L1");
        vm.stopPrank();

        // user2 => joins league1 & league2
        vm.startPrank(user2);
        IERC20(SEPOLIA_USDC).approve(league1, 10_000e6);
        League_TESTNET(league1).joinSeason("User2SameName");
        // tries the same name in league2 => it's a fresh league, no conflict
        IERC20(SEPOLIA_USDC).approve(league2, 20_000e6);
        League_TESTNET(league2).joinSeason("User2SameName");
        vm.stopPrank();

        // user2 => tries to re-join league1 => revert "TEAM_NAME_MISMATCH"
        vm.startPrank(user2);
        vm.expectRevert(bytes("TEAM_ALREADY_JOINED"));
        League_TESTNET(league1).joinSeason("User2SameName");
        vm.stopPrank();

        // user2 => tries to join league1 with a different name => revert "TEAM_NAME_MISMATCH"
        vm.startPrank(user2);
        vm.expectRevert(bytes("TEAM_ALREADY_JOINED"));
        League_TESTNET(league1).joinSeason("AnotherName");
        vm.stopPrank();

        // user3 => joins league2
        vm.startPrank(user3);
        IERC20(SEPOLIA_USDC).approve(league2, 20_000e6);
        League_TESTNET(league2).joinSeason("User3L2");
        vm.stopPrank();

        // Check factory.getActiveLeagues
        {
            address[] memory u1Leagues = factory.getActiveLeagues(user1);
            assertEq(u1Leagues.length, 1, "user1 active leagues mismatch");
            assertEq(u1Leagues[0], league1, "user1 missing league1");

            address[] memory u2Leagues = factory.getActiveLeagues(user2);
            assertEq(u2Leagues.length, 2, "user2 active leagues mismatch");
            // check membership
            bool foundL1;
            bool foundL2;
            for (uint256 i; i < u2Leagues.length; i++) {
                if (u2Leagues[i] == league1) foundL1 = true;
                if (u2Leagues[i] == league2) foundL2 = true;
            }
            assertTrue(foundL1 && foundL2, "user2 missing league1 or league2");

            address[] memory u3Leagues = factory.getActiveLeagues(user3);
            assertEq(u3Leagues.length, 1, "user3 active leagues mismatch");
            assertEq(u3Leagues[0], league2, "user3 missing league2");
        }
    }

    // ----------------------------------------------------------------
    // Test: Commissioner sets treasurer, depositToVault + withdrawFromVault
    // ----------------------------------------------------------------
    function testTreasurerVaultInteraction() public {
        // commissioner1 -> create league
        vm.startPrank(commissioner1);
        IERC20(SEPOLIA_USDC).approve(address(factory), 15_000e6);
        address leagueAddr = factory.createLeague("VaultLeague", 15_000e6, "CommishVault");
        vm.stopPrank();

        League_TESTNET league = League_TESTNET(leagueAddr);

        // commissioner1 => add treasurer1
        vm.startPrank(commissioner1);
        league.addTreasurer(treasurer1);
        vm.stopPrank();

        // user1 => join
        vm.startPrank(user1);
        IERC20(SEPOLIA_USDC).approve(leagueAddr, 15_000e6);
        league.joinSeason("User1Vault");
        vm.stopPrank();

        // league has 15k from commish + 15k from user1 => 30k
        assertEq(league.cashBalance(), 30_000e6, "league cash mismatch");

        // treasurer1 => deposit half => 15k into the wrapper
        vm.startPrank(treasurer1);
        league.depositToVault(address(wrapper), 15_000e6);
        vm.stopPrank();

        // check league's vault/cash
        assertEq(league.cashBalance(), 15_000e6, "cash after deposit mismatch");
        uint256 vaultBal = league.totalVaultBalance();
        assertEq(vaultBal, 15_000e6, "vaultBal mismatch");
        assertEq(league.totalLeagueBalance(), 30_000e6, "total balance mismatch");

        // treasurer1 => partial withdraw => 5k shares
        vm.startPrank(treasurer1);
        league.withdrawFromVault(address(wrapper), 5_000e6);
        vm.stopPrank();

        // now league's cash => 20k, vault => 10k, total => 30k
        assertEq(league.cashBalance(), 20_000e6, "league cash after partial vault withdraw mismatch");
        assertEq(league.totalVaultBalance(), 10_000e6, "league vault after partial withdraw mismatch");
        assertEq(league.totalLeagueBalance(), 30_000e6, "league total mismatch");

        // treasurer2 tries to deposit => revert, not treasurer
        vm.startPrank(treasurer2);
        IERC20(SEPOLIA_USDC).approve(leagueAddr, 5_000e6);
        vm.expectRevert(); // missing TREASURER_ROLE
        league.depositToVault(address(wrapper), 5_000e6);
        vm.stopPrank();
    }

    // ----------------------------------------------------------------
    // Test: allocateReward + claimReward => reward NFT minted
    // ----------------------------------------------------------------
    function testRewardFlow() public {
        // 1) commish1 => create league
        vm.startPrank(commissioner1);
        IERC20(SEPOLIA_USDC).approve(address(factory), 10_000e6);
        address leagueAddr = factory.createLeague("RewardLeague", 10_000e6, "CommishRewardTeam");
        vm.stopPrank();

        League_TESTNET league = League_TESTNET(leagueAddr);

        // user1 => join
        vm.startPrank(user1);
        IERC20(SEPOLIA_USDC).approve(leagueAddr, 10_000e6);
        league.joinSeason("User1Reward");
        vm.stopPrank();

        // 2) Commish allocates a reward to user1 => 2k
        vm.startPrank(commissioner1);
        league.allocateReward(user1, "TopScorer", 2_000e6);
        vm.stopPrank();

        // user1 has a reward of 2k => teamRewards[user1]
        // user1 claims => triggers mintReward from leagueRewardNFT
        vm.startPrank(user1);
        league.claimReward("ipfs://someHash");
        vm.stopPrank();

        // Check user1's final USDC => got 2k from the league
        uint256 finalBal = IERC20(SEPOLIA_USDC).balanceOf(user1);
        // started with 50k, spent 10k to join => 40k left, now +2k => 42k
        assertEq(finalBal, 42_000e6, "User1 final USDC after claiming mismatch");

        // Check reward NFT minted => token #1 => user1 owns it
        LeagueRewardNFT_TESTNET nft = LeagueRewardNFT_TESTNET(factory.leagueRewardNFT());
        // if we assume the first minted ID is 1, we do:
        address ownerOf1 = nft.ownerOf(1);
        assertEq(ownerOf1, user1, "Reward NFT #1 not owned by user1");
    }

    // ----------------------------------------------------------------
    // Test: closeLeague => removes from factory, league no longer active
    // ----------------------------------------------------------------
    function testCloseLeague() public {
        // commish2 => create league
        vm.startPrank(commissioner2);
        IERC20(SEPOLIA_USDC).approve(address(factory), 10_000e6);
        address leagueAddr = factory.createLeague("CloseLeague", 10_000e6, "CommishCloseTeam");
        vm.stopPrank();

        // user1 => join
        vm.startPrank(user1);
        IERC20(SEPOLIA_USDC).approve(leagueAddr, 10_000e6);
        League_TESTNET(leagueAddr).joinSeason("User1Close");
        vm.stopPrank();

        // The league has 20k. Commish2 calls closeLeague => all USDC to commish2, factory removeLeague
        vm.startPrank(commissioner2);
        League_TESTNET(leagueAddr).closeLeague();
        vm.stopPrank();

        // confirm factory data
        address stored = factory.leagueAddress("CloseLeague");
        assertEq(stored, address(0), "CloseLeague not removed from factory");
        // league no longer in getActiveLeagues
        address[] memory user1Leagues = factory.getActiveLeagues(user1);
        for (uint256 i; i < user1Leagues.length; i++) {
            require(user1Leagues[i] != leagueAddr, "closed league still active for user1");
        }

        // confirm user1 can't do anything => notActive
        vm.startPrank(user1);
        vm.expectRevert(bytes("LEAGUE_NOT_ACTIVE"));
        League_TESTNET(leagueAddr).joinSeason("ShouldFail");
        vm.stopPrank();
    }

    // ----------------------------------------------------------------
    // Additional Fuzzing Example
    // ----------------------------------------------------------------
    function testFuzzRemoveTeam(uint256 removeIndex) public {
        // commish1 => create league
        vm.startPrank(commissioner1);
        IERC20(SEPOLIA_USDC).approve(address(factory), 15_000e6);
        address fuzzLeague = factory.createLeague("FuzzRemove", 15_000e6, "CommishFuzzRemove");
        vm.stopPrank();

        League_TESTNET league = League_TESTNET(fuzzLeague);

        // user1 => join
        vm.startPrank(user1);
        IERC20(SEPOLIA_USDC).approve(fuzzLeague, 15_000e6);
        league.joinSeason("User1FuzzRem");
        vm.stopPrank();

        // user2 => join
        vm.startPrank(user2);
        IERC20(SEPOLIA_USDC).approve(fuzzLeague, 15_000e6);
        league.joinSeason("User2FuzzRem");
        vm.stopPrank();

        // We have commish + user1 + user2 = 3 teams
        // removeIndex in [0..10], if removeIndex > #teams or user2 => we'll revert or do partial scenario
        removeIndex = bound(removeIndex, 0, 2);
        address teamToRemove = league.currentSeason().teams[removeIndex];
        if (teamToRemove == commissioner1) {
            // remove commish's team => possible, but let's just do it
            vm.startPrank(commissioner1);
            league.removeTeam(teamToRemove);
            vm.stopPrank();
            // check they're no longer active
            bool active = league.isTeamActive(teamToRemove);
            assertFalse(active, "Commissioner still active after remove");
        } else {
            // user1 or user2
            vm.startPrank(commissioner1);
            league.removeTeam(teamToRemove);
            vm.stopPrank();
            bool active = league.isTeamActive(teamToRemove);
            assertFalse(active, "User still active after removeTeam fuzz");
        }
    }
}
