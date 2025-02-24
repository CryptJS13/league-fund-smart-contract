// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/League_TESTNET.sol";
import "../src/LeagueFactory_TESTNET.sol";
import "../src/interfaces/ILeagueFactory.sol";

/**
 * @title League_TESTNET Unit Tests
 * @notice Demonstrates testing of League_TESTNET functions using Foundry,
 *         including removeTeam(), getAllTeams(), closeLeague(), etc.
 *         Assumes we are forking Base Sepolia in foundry.toml or via CLI flags.
 */
contract League_TESTNET_Test is Test {
    League_TESTNET league;

    // Example constructor params:
    string internal constant LEAGUE_NAME = "MyLeague";
    uint256 internal constant INITIAL_DUES = 100e6; // e.g., 100 USDC (6 decimals)
    string internal constant INITIAL_TEAM_NAME = "CommissionerTeam";

    // Roles
    bytes32 public constant COMMISSIONER_ROLE = keccak256("COMMISSIONER_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    // The USDC address on Base Sepolia (as stated in your contract)
    address internal constant USDC_ADDRESS = 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B;

    // We'll define addresses for testing
    address internal commissioner; // Deploy & has COMMISSIONER_ROLE
    address internal user1; // A random user who will join the league
    address internal user2; // Another user or treasurer
    LeagueFactory_TESTNET internal factory; // We'll set this as a mock or use a real one if desired

    /**
     * @dev Runs before each test. Sets up fresh state:
     *      - Deploys the league contract with given constructor arguments.
     *      - (Optional) Sets up token balances & approvals if running on a fork.
     */
    function setUp() public {
        // 1. Create "labeled" test addresses
        commissioner = makeAddr("Commissioner");
        user1 = makeAddr("User1");
        user2 = makeAddr("User2");

        // 2. Pretend the league was deployed by some factory address (or real one).
        factory = new LeagueFactory_TESTNET();

        // 3. Give commissioner, user1, user2 some USDC & ETH on a fork
        //    (Here we mock a "usdcHolder" who has enough USDC.)
        //    Adjust these addresses to real whales if needed on a real fork.
        address usdcHolder = address(0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F);
        vm.startPrank(usdcHolder);
        IERC20(USDC_ADDRESS).transfer(commissioner, 1000e6);
        IERC20(USDC_ADDRESS).transfer(user1, 1000e6);
        IERC20(USDC_ADDRESS).transfer(user2, 1000e6);
        vm.stopPrank();

        // Give them some ETH for gas
        vm.deal(commissioner, 1 ether);
        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);

        // 4. Deploy the league contract
        vm.startPrank(commissioner);
        IERC20(USDC_ADDRESS).approve(address(factory), INITIAL_DUES);
        address leagueAddr = factory.createLeague(LEAGUE_NAME, INITIAL_DUES, INITIAL_TEAM_NAME);
        vm.stopPrank();
        league = League_TESTNET(leagueAddr);
    }

    /**
     * @dev Test that constructor sets initial state correctly.
     */
    function testInitialState() public view {
        // Check league name
        assertEq(league.name(), LEAGUE_NAME, "League name mismatch");

        // There's exactly 1 season in the contract because `initLeague` is called in constructor
        League_TESTNET.SeasonData memory initSeason = league.currentSeason();
        assertEq(initSeason.dues, INITIAL_DUES, "Initial season dues mismatch");
        assertEq(initSeason.teams.length, 1, "Should have exactly 1 team in the initial season");

        // The first team is the commissioner's
        address initTeam = initSeason.teams[0];
        assertEq(initTeam, commissioner, "Initial team wallet mismatch");

        // Confirm commissioner has the COMMISSIONER_ROLE
        bool isCommish = league.hasRole(COMMISSIONER_ROLE, commissioner);
        assertTrue(isCommish, "Commissioner role not set correctly");

        // Confirm commissioner also has the TREASURER_ROLE
        bool isTreasurer = league.hasRole(TREASURER_ROLE, commissioner);
        assertTrue(isTreasurer, "Commissioner should also be Treasurer initially");
    }

    /**
     * @dev Test that the commissioner can create a new season.
     */
    function testCreateSeason() public {
        // Impersonate commissioner
        vm.startPrank(commissioner);

        // Create new season
        league.createSeason(50e6);

        // Confirm we now have 2 seasons in total
        League_TESTNET.SeasonData memory current = league.currentSeason();
        assertEq(current.dues, 50e6, "Dues mismatch for new season");

        vm.stopPrank();
    }

    /**
     * @dev Test that a non-commissioner cannot create a season.
     */
    function testNonCommissionerCannotCreateSeason() public {
        vm.startPrank(user1);
        vm.expectRevert(); // We expect an AccessControl revert
        league.createSeason(50e6);
        vm.stopPrank();
    }

    /**
     * @dev Test joining a season by paying dues in USDC.
     *      user1 must approve the League to spend their USDC first.
     */
    function testJoinSeason() public {
        vm.startPrank(user1);

        // 1. Approve the league to spend user1's USDC
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);

        // 2. Join the season
        league.joinSeason("User1Team");
        vm.stopPrank();

        // 3. Check the new team
        League_TESTNET.TeamData[] memory teams = league.getActiveTeams();
        assertEq(teams.length, 2, "Should be 2 teams in the current season");
        assertEq(teams[1].name, "User1Team", "Team name mismatch");
        assertEq(teams[1].wallet, user1, "Team wallet mismatch");
    }

    /**
     * @dev Test that joining with an existing team name reverts with "TEAM_NAME_EXISTS".
     */
    function testCannotJoinWithDuplicateTeamName() public {
        // The constructor used "CommissionerTeam" as the initial name
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);

        // Attempt to join with the same name as the existing team
        vm.expectRevert(bytes("TEAM_NAME_EXISTS"));
        league.joinSeason(INITIAL_TEAM_NAME);
        vm.stopPrank();
    }

    /**
     * @dev Test that we cannot joinSeason with a wallet that already joined.
     */
    function testCannotJoinWithDuplicateWallet() public {
        // The constructor already used "commissioner" as a participant
        vm.startPrank(commissioner);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);

        // Try to join the same wallet with a different name
        vm.expectRevert(bytes("TEAM_WALLET_EXISTS"));
        league.joinSeason("AnotherCommishTeamName");
        vm.stopPrank();
    }

    /**
     * @dev Test commissioner role transfer via setCommissioner().
     */
    function testSetCommissioner() public {
        // Start as the original commissioner
        vm.startPrank(commissioner);

        // Change commissioner to user1
        league.setCommissioner(user1);
        vm.stopPrank();

        // Now user1 should have the COMMISSIONER_ROLE
        bool user1IsCommish = league.hasRole(COMMISSIONER_ROLE, user1);
        assertTrue(user1IsCommish, "User1 should be new commissioner");

        // The old commissioner should no longer have COMMISSIONER_ROLE
        bool oldCommishIsStill = league.hasRole(COMMISSIONER_ROLE, commissioner);
        assertFalse(oldCommishIsStill, "Old commissioner should have lost the role");
    }

    /**
     * @dev Test that only the commissioner can set a new commissioner.
     */
    function testOnlyCommissionerCanSetCommissioner() public {
        vm.startPrank(user1);
        // user1 is not the commissioner in the initial state
        vm.expectRevert();
        league.setCommissioner(user2);
        vm.stopPrank();
    }

    /**
     * @dev Test adding and removing a treasurer.
     */
    function testTreasurerRoleManagement() public {
        vm.startPrank(commissioner);
        league.addTreasurer(user1);
        vm.stopPrank();

        bool user1IsTreasurer = league.hasRole(TREASURER_ROLE, user1);
        assertTrue(user1IsTreasurer, "User1 should be a treasurer now");

        // Remove them
        vm.startPrank(commissioner);
        league.removeTreasurer(user1);
        vm.stopPrank();

        user1IsTreasurer = league.hasRole(TREASURER_ROLE, user1);
        assertFalse(user1IsTreasurer, "User1 should no longer be a treasurer");
    }

    /**
     * @dev Test getAllTeams() vs getActiveTeams().
     *      getAllTeams() includes *every* address that ever joined,
     *      while getActiveTeams() only returns the teams in the *current* season.
     */
    function testGetAllTeams() public {
        // user1 joins the league
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // user2 joins the league
        vm.startPrank(user2);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);
        league.joinSeason("User2Team");
        vm.stopPrank();

        // Both user1 & user2 are in the first season
        League_TESTNET.TeamData[] memory activeTeams1 = league.getActiveTeams();
        assertEq(activeTeams1.length, 3, "3 teams total in active season (commish + 2)");

        // Check getAllTeams
        League_TESTNET.TeamData[] memory allT = league.getAllTeams();
        assertEq(allT.length, 3, "All teams should also be 3 so far");

        // Now commissioner creates a new season
        vm.startPrank(commissioner);
        league.createSeason(0);
        vm.stopPrank();

        // The new season has 0 teams initially
        League_TESTNET.TeamData[] memory activeTeams2 = league.getActiveTeams();
        assertEq(activeTeams2.length, 0, "No teams in new season by default");

        // But getAllTeams() still includes the old 3 teams that joined previously
        League_TESTNET.TeamData[] memory allT2 = league.getAllTeams();
        assertEq(allT2.length, 3, "allTeams includes historical players");
    }

    /**
     * @dev Test removing a team from the current season.
     */
    function testRemoveTeam() public {
        // user1 joins
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // Now commissioner removes user1 from the current season
        vm.startPrank(commissioner);
        league.removeTeam(user1);
        vm.stopPrank();

        // Confirm user1 is no longer active in the current season
        bool active = league.isTeamActive(user1);
        assertFalse(active, "User1 should not be active after removal");

        // Also check that the user was removed from the array
        League_TESTNET.SeasonData memory season = league.currentSeason();
        for (uint256 i = 0; i < season.teams.length; i++) {
            require(season.teams[i] != user1, "User1 not removed from array");
        }
    }

    /**
     * @dev Test that only commissioner can remove a team.
     */
    function testNonCommissionerCannotRemoveTeam() public {
        // user1 joins
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // user2 tries to remove user1, but user2 is not commissioner
        vm.startPrank(user2);
        vm.expectRevert(); // AccessControl revert
        league.removeTeam(user1);
        vm.stopPrank();
    }

    /**
     * @dev Test closeLeague() functionality:
     *      1) Creates a new season with 0 dues
     *      2) Transfers full league balance to the commissioner
     *      3) Calls removeLeague() on the factory
     */
    function testCloseLeague() public {
        // 1) Let user1 join for some extra funds in the league
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // 2) Check the league's balance
        uint256 leagueBalanceBefore = IERC20(USDC_ADDRESS).balanceOf(address(league));

        // 3) Commissioner closes the league
        vm.startPrank(commissioner);
        league.closeLeague();
        vm.stopPrank();

        // 4) Confirm the league's USDC balance is now 0
        uint256 leagueBalanceAfter = IERC20(USDC_ADDRESS).balanceOf(address(league));
        assertEq(leagueBalanceAfter, 0, "League should have 0 after close");

        // 5) Confirm commissioner got the league balance
        uint256 commishBalance = IERC20(USDC_ADDRESS).balanceOf(commissioner);
        // The commissioner started with 1000e6, spent 100e6 on createLeague,
        // gained leagueBalanceBefore from closeLeague.
        // The final must be: initial(1000e6) - 100e6 + leagueBalanceBefore = 900e6 + leagueBalanceBefore.
        // But you can do a more direct check if you prefer:
        // commishBalance should have incremented by leagueBalanceBefore:
        //   commishBalanceBefore + leagueBalanceBefore == commishBalance
        // We'll do it roughly:
        assertEq(commishBalance, 1000e6 - INITIAL_DUES + leagueBalanceBefore, "Commissioner's final USDC mismatch");

        // 6) Confirm a new season with 0 dues was created
        League_TESTNET.SeasonData memory newSeason = league.currentSeason();
        assertEq(newSeason.dues, 0, "Dues in new season should be 0 after closeLeague");

        // 7) The league calls removeLeague() on the factory.
        //    So the factory should have removed the league from its storage
        address storedLeague = factory.leagueAddress(LEAGUE_NAME);
        assertEq(storedLeague, address(0), "Factory should no longer store the league address");
    }

    /**
     * @dev Only the commissioner can allocate a reward,
     *      and the total must not exceed the league's balance.
     */
    function testAllocateReward() public {
        // Let user1 join so the league has some USDC
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // Check the league's current balance
        uint256 leagueBal = league.leagueBalance();
        assertEq(leagueBal, INITIAL_DUES * 2, "League balance mismatch after user1 joined");

        // Non-commissioner tries to allocate reward -> revert
        vm.startPrank(user1);
        vm.expectRevert(); // AccessControl
        league.allocateReward(user2, 10e6);
        vm.stopPrank();

        // Commissioner can allocate
        vm.startPrank(commissioner);
        league.allocateReward(user1, 10e6);
        vm.stopPrank();

        // totalClaimableRewards should increase
        uint256 totalClaimable = league.totalClaimableRewards();
        assertEq(totalClaimable, 10e6, "totalClaimableRewards mismatch");

        // Now if we try to allocate more than leagueBal, it should revert
        vm.startPrank(commissioner);
        vm.expectRevert(bytes("INSUFFICIENT_BALANCE"));
        league.allocateReward(user1, leagueBal + 1);
        vm.stopPrank();
    }

    /**
     * @dev Test that users can claim previously allocated rewards
     *      and that the reward array is cleared afterward.
     */
    function testClaimReward() public {
        // Let user1 join
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);
        league.joinSeason("User1Team");
        vm.stopPrank();

        // Let commissioner allocate some rewards to user1
        uint256 rewardAmount = 30e6;
        vm.startPrank(commissioner);
        league.allocateReward(user1, rewardAmount);
        vm.stopPrank();

        // user1's USDC balance before claiming
        uint256 user1BalBefore = IERC20(USDC_ADDRESS).balanceOf(user1);

        // user1 claims
        vm.startPrank(user1);
        league.claimReward();
        vm.stopPrank();

        // user1's USDC balance after claiming
        uint256 user1BalAfter = IERC20(USDC_ADDRESS).balanceOf(user1);
        assertEq(user1BalAfter, user1BalBefore + rewardAmount, "User1 did not receive correct reward");

        // totalClaimableRewards should have decreased
        uint256 totalClaimable = league.totalClaimableRewards();
        assertEq(totalClaimable, 0, "totalClaimableRewards should be 0 after claiming");

        // Check that teamRewards[user1] is cleared
        vm.expectRevert(); // Not available because it's empty
        league.teamRewards(user1, 0);
    }
}
