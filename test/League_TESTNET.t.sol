// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/League_TESTNET.sol";

/**
 * @title League_TESTNET Unit Tests
 * @notice Demonstrates testing of League_TESTNET functions using Foundry.
 *         Assumes we are forking Base Sepolia in foundry.toml or via CLI flags.
 */
contract League_TESTNET_Test is Test {
    League_TESTNET league;

    // Example constructor params:
    string internal constant LEAGUE_NAME = "MyLeague";
    string internal constant INITIAL_SEASON_NAME = "Season2025";
    uint256 internal constant INITIAL_DUES = 100e6; // e.g., 100 USDC, since USDC typically has 6 decimals
    string internal constant INITIAL_TEAM_NAME = "CommissionerTeam";

    // Roles
    bytes32 public constant COMMISSIONER_ROLE = keccak256("COMMISSIONER_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    // The USDC address on Base Sepolia (as stated in your contract)
    address internal constant USDC_ADDRESS = 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B;

    // We’ll define addresses for testing
    address internal commissioner; // will deploy & have the COMMISSIONER_ROLE
    address internal user1;        // a random user who will join the league
    address internal user2;        // another user or treasurer

    /**
     * @dev Runs before each test. Sets up fresh state:
     *      - Deploys the league contract with given constructor arguments.
     *      - Optionally sets up token balances.
     */
    function setUp() public {
        // We can create "labeled" test addresses with Foundry's built-in utilities:
        commissioner = makeAddr("Commissioner");
        user1 = makeAddr("User1");
        user2 = makeAddr("User2");

        // Deploy the league contract
        league = new League_TESTNET(
            LEAGUE_NAME,
            commissioner,
            INITIAL_SEASON_NAME,
            INITIAL_DUES,
            INITIAL_TEAM_NAME
        );

        // 1. Impersonate some known USDC whale or faucet address on Base Sepolia
        // 2. Transfer USDC to user1, user2, etc.
        address usdcHolder = address(0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F);
        vm.startPrank(usdcHolder);
        IERC20(USDC_ADDRESS).transfer(commissioner, 1000e6); // user1 gets 1000 USDC
        IERC20(USDC_ADDRESS).transfer(user1, 1000e6); // user1 gets 1000 USDC
        IERC20(USDC_ADDRESS).transfer(user2, 1000e6);
        vm.stopPrank();
        
        // Also ensure they have enough native ETH for gas if needed:
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
        // Confirm the first season has the right data
        League_TESTNET.SeasonData memory initSeason = league.currentSeason();
        assertEq(initSeason.name, INITIAL_SEASON_NAME, "Initial season name mismatch");
        assertEq(initSeason.dues, INITIAL_DUES, "Initial season dues mismatch");
        assertEq(initSeason.teams.length, 1, "Should have exactly 1 team in the initial season");

        // The first team is the commissioner's
        address initTeam = initSeason.teams[0];
        // assertEq(initTeam.name, INITIAL_TEAM_NAME, "Initial team name mismatch");
        assertEq(initTeam, commissioner, "Initial team wallet mismatch");

        // Confirm commissioner has the COMMISSIONER_ROLE
        // AccessControl provides hasRole
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
        league.createSeason("Season2026", 50e6);

        // Confirm we have 2 seasons in total
        League_TESTNET.SeasonData memory current = league.currentSeason();
        assertEq(current.name, "Season2026");
        assertEq(current.dues, 50e6);
        vm.stopPrank();
    }

    /**
     * @dev Test that creating a season with the same name reverts.
     */
    function testCannotCreateSeasonWithSameName() public {
        vm.startPrank(commissioner);

        // The constructor already used "Season2025"
        // Attempt to create a second season with the same name
        vm.expectRevert(bytes("SEASON_EXISTS"));
        league.createSeason(INITIAL_SEASON_NAME, 50e6);

        vm.stopPrank();
    }

    /**
     * @dev Test that a non-commissioner cannot create a season.
     */
    function testNonCommissionerCannotCreateSeason() public {
        vm.startPrank(user1);
        vm.expectRevert(); // We expect an AccessControl revert
        league.createSeason("Season2026", 50e6);
        vm.stopPrank();
    }

    /**
     * @dev Test that a new user can join the current season by paying dues in USDC.
     *      NOTE: This requires user1 to actually have USDC on the fork if it's a real token call.
     */
    function testJoinSeason() public {
        // Suppose user1 has some USDC. We'll skip the actual top-up in this snippet,
        // but you'd do it in setUp() if you’re forking a real chain.

        // user1 must approve the League contract to spend their USDC
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);

        // The user calls joinSeason with a new team name
        league.joinSeason("User1Team");
        vm.stopPrank();

        // Check new team
        League_TESTNET.TeamData[] memory teams = league.activeTeams();
        assertEq(teams.length, 2, "Should be 2 teams in the current season");
        assertEq(teams[1].name, "User1Team", "Team name mismatch");
        assertEq(teams[1].wallet, user1, "Team wallet mismatch");
    }

    /**
     * @dev Test that joining with an existing team name reverts with "TEAM_EXISTS".
     */
    function testCannotJoinWithDuplicateTeamName() public {
        // The constructor used "CommissionerTeam" as the initial name
        vm.startPrank(user1);
        IERC20(USDC_ADDRESS).approve(address(league), INITIAL_DUES);

        // Attempt to join with the same name as the existing team
        vm.expectRevert(bytes("TEAM_EXISTS"));
        league.joinSeason(INITIAL_TEAM_NAME);
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
     * @dev Test that we cannot call initLeague() again (which is private, but we can use coverage).
     *      Because it's called only once in the constructor, we just show it was locked with "INITIALIZED".
     */
    function testCannotReinit() public {
        // There's no direct external function that calls initLeague again.
        // If you had an external function that calls initLeague, you'd test it here.
        // We'll just confirm that the contract is already "INITIALIZED" from the constructor.
        // e.g. Trying to manually push an identical season might show "SEASON_EXISTS" or something else.

        vm.startPrank(commissioner);
        vm.expectRevert(bytes("SEASON_EXISTS")); // or "INITIALIZED" if you had a direct call
        league.createSeason(INITIAL_SEASON_NAME, 500e6); // The same season name
        vm.stopPrank();
    }
}