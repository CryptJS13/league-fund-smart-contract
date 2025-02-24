// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/LeagueFactory_TESTNET.sol";
import "../src/League_TESTNET.sol";
import "../src/interfaces/ILeague.sol";

/**
 * @title LeagueFactory_TESTNET Tests
 * @notice This suite tests the extended functionality of LeagueFactory_TESTNET:
 *         1) createLeague
 *         2) removeLeague
 *         3) getActiveLeagues
 */
contract LeagueFactory_TESTNET_Test is Test {
    LeagueFactory_TESTNET factory;

    // Example parameters
    string internal constant LEAGUE_NAME = "MyLeague";
    uint256 internal constant INITIAL_DUES = 100e6; // 100 USDC (6 decimals)
    string internal constant INITIAL_TEAM_NAME = "CommissionerTeam";

    // We'll define a second league name for multi-league tests
    string internal constant LEAGUE_NAME_2 = "MyLeague2";
    uint256 internal constant DUES_LEAGUE_2 = 50e6;

    // Addresses
    address internal constant TEST_USDC = 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B;
    address internal deployer; // Will create factory
    address internal user1; // Will create or join leagues
    address internal user2; // Another user

    function setUp() public {
        // 1. Create test addresses
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // 2. Deploy factory from "deployer"
        vm.startPrank(deployer);
        factory = new LeagueFactory_TESTNET();
        vm.stopPrank();

        // 3. Ensure user1 & user2 have USDC and have approved the factory.
        address usdcHolder = address(0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F);
        vm.startPrank(usdcHolder);
        IERC20(TEST_USDC).transfer(user1, 1000e6);
        IERC20(TEST_USDC).transfer(user2, 1000e6);
        vm.stopPrank();

        // Give them some ETH for tx gas if needed:
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);

        // Now user1 & user2 each approve factory
        vm.startPrank(user1);
        IERC20(TEST_USDC).approve(address(factory), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        IERC20(TEST_USDC).approve(address(factory), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @dev Test creating a league and verify that everything is set properly.
     */
    function testCreateLeague() public {
        vm.startPrank(user1);
        address leagueAddress = factory.createLeague(LEAGUE_NAME, INITIAL_DUES, INITIAL_TEAM_NAME);
        vm.stopPrank();

        // Basic checks
        assertTrue(leagueAddress != address(0), "League address should not be zero");

        // Check the stored mapping
        address storedAddress = factory.leagueAddress(LEAGUE_NAME);
        assertEq(storedAddress, leagueAddress, "Stored league address mismatch");

        // Check allLeagues array
        uint256 allLeaguesCount = factory.allLeaguesLength();
        assertEq(allLeaguesCount, 1, "allLeagues should have length 1");

        // Confirm the newly created league is in allLeagues
        address firstInList = factory.allLeagues(0);
        assertEq(firstInList, leagueAddress, "First league in array mismatch");

        // Check data inside the League contract
        League_TESTNET deployedLeague = League_TESTNET(leagueAddress);
        string memory actualLeagueName = deployedLeague.name();
        assertEq(actualLeagueName, LEAGUE_NAME, "League name mismatch");

        // Confirm the dues are set
        League_TESTNET.SeasonData memory season = deployedLeague.currentSeason();
        assertEq(season.dues, INITIAL_DUES, "Initial Dues mismatch");
    }

    /**
     * @dev Test that creating a league with the same name fails with the "LEAGUE_EXISTS" error.
     */
    function testCannotCreateLeagueWithSameName() public {
        vm.startPrank(user1);
        factory.createLeague(LEAGUE_NAME, INITIAL_DUES, INITIAL_TEAM_NAME);

        // Attempt second creation with the same leagueName -> should revert
        vm.expectRevert(bytes("LEAGUE_EXISTS"));
        factory.createLeague(LEAGUE_NAME, INITIAL_DUES, INITIAL_TEAM_NAME);
        vm.stopPrank();
    }

    /**
     * @dev Test removing a league from the factory by calling removeLeague().
     *      Since removeLeague() requires msg.sender == the league address, we impersonate that league contract.
     *      Typically the league calls `closeLeague()`, which in turn calls `removeLeague()`.
     */
    function testRemoveLeague() public {
        // 1. user1 creates a league
        vm.startPrank(user1);
        address leagueAddr = factory.createLeague(LEAGUE_NAME, INITIAL_DUES, INITIAL_TEAM_NAME);
        vm.stopPrank();

        // 2. Check we have 1 league
        assertEq(factory.allLeaguesLength(), 1, "Should have 1 league in the factory");

        // 3. Attempt removal from a random address -> revert with "NOT_LEAGUE"
        vm.startPrank(user2);
        vm.expectRevert(bytes("NOT_LEAGUE"));
        factory.removeLeague();
        vm.stopPrank();

        // 4. Remove from the league's own perspective
        //    In actual usage, the league calls `ILeagueFactory(FACTORY).removeLeague()` from `closeLeague()`.
        //    Here we can simulate that call by impersonating the league contract:
        vm.startPrank(leagueAddr);
        factory.removeLeague();
        vm.stopPrank();

        // 5. Confirm the league was removed from mappings & array
        address storedLeague = factory.leagueAddress(LEAGUE_NAME);
        assertEq(storedLeague, address(0), "leagueAddress mapping not cleared");

        string memory storedName = factory.leagueName(leagueAddr);
        assertEq(bytes(storedName).length, 0, "leagueName mapping not cleared");

        assertEq(factory.allLeaguesLength(), 0, "Should have 0 leagues in the factory now");
    }

    /**
     * @dev Test getActiveLeagues by creating multiple leagues, joining them from the same user,
     *      and verifying the function returns the correct addresses.
     */
    function testGetActiveLeagues() public {
        // user1 creates League1
        vm.startPrank(user1);
        address league1 = factory.createLeague(LEAGUE_NAME, INITIAL_DUES, INITIAL_TEAM_NAME);
        vm.stopPrank();

        // user2 creates League2
        vm.startPrank(user2);
        address league2 = factory.createLeague(LEAGUE_NAME_2, DUES_LEAGUE_2, "Commissioner2");
        vm.stopPrank();

        // By design, the league creator automatically is a "team" in that league,
        // so user1 is active in league1, user2 is active in league2.

        // Let's have user1 also join league2:
        // 1. Approve league2 to pull USDC
        vm.startPrank(user1);
        // user1 already approved the factory, but we need to approve league2 if `joinSeason` requires direct xferFrom user1->league2
        IERC20(TEST_USDC).approve(league2, type(uint256).max);

        // 2. joinSeason
        ILeague(league2).joinSeason("User1TeamInLeague2");
        vm.stopPrank();

        // user1 is active in BOTH league1 and league2 now.
        // Let's have user2 join league1 for fun:
        vm.startPrank(user2);
        IERC20(TEST_USDC).approve(league1, type(uint256).max);
        ILeague(league1).joinSeason("User2TeamInLeague1");
        vm.stopPrank();

        // user2 is active in BOTH league1 and league2 as well.

        // Check user1's active leagues
        address[] memory leaguesUser1 = factory.getActiveLeagues(user1);
        // We expect 2 leagues
        assertEq(leaguesUser1.length, 2, "User1 should be active in 2 leagues");
        // The order depends on creation order or iteration order in your factory.
        // Typically it will be [league1, league2].
        // We'll do a quick check that each one is in the set:
        bool foundL1;
        bool foundL2;
        for (uint256 i = 0; i < leaguesUser1.length; i++) {
            if (leaguesUser1[i] == league1) foundL1 = true;
            if (leaguesUser1[i] == league2) foundL2 = true;
        }
        assertTrue(foundL1 && foundL2, "User1 missing expected leagues");

        // Check user2's active leagues
        address[] memory leaguesUser2 = factory.getActiveLeagues(user2);
        assertEq(leaguesUser2.length, 2, "User2 should be active in 2 leagues");
        foundL1 = false;
        foundL2 = false;
        for (uint256 i = 0; i < leaguesUser2.length; i++) {
            if (leaguesUser2[i] == league1) foundL1 = true;
            if (leaguesUser2[i] == league2) foundL2 = true;
        }
        assertTrue(foundL1 && foundL2, "User2 missing expected leagues");
    }
}
