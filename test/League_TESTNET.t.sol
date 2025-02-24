// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/League_TESTNET.sol";
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
    address internal factory; // We'll set this as a mock or use a real one if desired

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
        factory = makeAddr("MockFactory");

        // 3. Deploy the league contract
        vm.prank(factory); // The next creation is "from" the factory
        league = new League_TESTNET(LEAGUE_NAME, INITIAL_DUES, INITIAL_TEAM_NAME, commissioner);

        // 4. Give commissioner, user1, user2 some USDC & ETH on a fork
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
}
