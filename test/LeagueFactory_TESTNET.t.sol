// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/LeagueFactory_TESTNET.sol";
import "../src/League_TESTNET.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LeagueFactory_TESTNET Tests
 * @notice This test suite uses Foundry and forks the Base Sepolia testnet.
 */
contract LeagueFactory_TESTNET_Test is Test {
    LeagueFactory_TESTNET factory;

    // Example parameters for league creation
    string leagueName = "Premier League";
    string seasonName = "2025/26";
    uint256 dues = 100e6;
    string teamName = "Sample FC";

    address constant TEST_ACCOUNT = address(0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F);
    address constant TEST_USDC = address(0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B);

    /**
     * @dev We use setUp() to:
     *      Deploy a fresh instance of LeagueFactory_TESTNET on the fork.
     */
    function setUp() public {
        // Deploy the factory
        factory = new LeagueFactory_TESTNET();
        vm.startPrank(TEST_ACCOUNT);
        IERC20(TEST_USDC).approve(address(factory), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @dev Test creating a league and verify that all returned values and mappings are correct.
     */
    function testCreateLeague() public {
        vm.startPrank(TEST_ACCOUNT);
        // Call createLeague
        address leagueAddress = factory.createLeague(leagueName, seasonName, dues, teamName);

        // Basic checks
        assertTrue(leagueAddress != address(0), "League address should not be zero");

        // Check the stored mapping
        address storedAddress = factory.getLeague(leagueName);
        assertEq(storedAddress, leagueAddress, "Stored league address mismatch");

        // Check allLeagues array
        uint256 allLeaguesCount = factory.allLeaguesLength();
        assertEq(allLeaguesCount, 1, "allLeagues should have length 1");

        // Confirm the newly created league is in allLeagues
        address firstInList = factory.allLeagues(0);
        assertEq(firstInList, leagueAddress, "First league in array mismatch");

        // Optionally, if you need to verify data inside the League_TESTNET contract:
        League_TESTNET deployedLeague = League_TESTNET(leagueAddress);
        string memory actualLeagueName = deployedLeague.name();
        assertEq(actualLeagueName, leagueName, "League name mismatch in the deployed contract");
        vm.stopPrank();
    }

    /**
     * @dev Test that creating a league with the same name fails with the "LEAGUE_EXISTS" error.
     */
    function testCannotCreateLeagueWithSameName() public {
        vm.startPrank(TEST_ACCOUNT);
        // First creation
        factory.createLeague(leagueName, seasonName, dues, teamName);

        // Attempt second creation with the same leagueName -> should revert
        vm.expectRevert(bytes("LEAGUE_EXISTS"));
        factory.createLeague(leagueName, seasonName, dues, teamName);
        vm.stopPrank();
    }
}
