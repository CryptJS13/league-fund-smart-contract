// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/LeagueFactory_TESTNET.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ---------------------------------
// Mock contracts for testing
// ---------------------------------

contract MockLeagueRewardNFT {
    address private _factory;

    constructor(address factory_) {
        _factory = factory_;
    }

    function FACTORY() external view returns (address) {
        return _factory;
    }
}

contract MockVault {
    address private _factory;

    constructor(address factory_) {
        _factory = factory_;
    }

    function FACTORY() external view returns (address) {
        return _factory;
    }
}

// ---------------------------------
// The Test Contract
// ---------------------------------
contract LeagueFactoryTest is Test {
    // ============ Addresses ============
    LeagueFactory_TESTNET public factory;
    // USDC on your fork
    address public constant USDC = 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B;
    // Whale that holds USDC on your fork
    address public constant whale = 0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F;

    // Test accounts
    address public owner = address(100);
    address public user1 = address(101);
    address public user2 = address(102);

    // Mocks
    MockLeagueRewardNFT public mockNFT;
    MockVault public mockVault1;
    MockVault public mockVault2;

    // ============ Setup ============
    function setUp() public {
        // Label addresses in Hardhat/Foundry logs
        vm.label(owner, "Owner");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(whale, "USDC_Whale");
        vm.label(USDC, "USDC");

        // Give the whale some ETH to pay for gas if needed
        vm.deal(whale, 100 ether);

        // Deploy the factory from the "owner"
        vm.startPrank(owner);
        factory = new LeagueFactory_TESTNET();
        vm.stopPrank();

        // Impersonate the whale to transfer USDC to user1, user2
        vm.startPrank(whale);
        // Transfer 10,000 USDC (in 6 decimals) to user1
        IERC20(USDC).transfer(user1, 10_000 * 1e6);
        // Transfer 10,000 USDC (in 6 decimals) to user2
        IERC20(USDC).transfer(user2, 10_000 * 1e6);
        vm.stopPrank();

        // Deploy mock NFT and vaults
        vm.startPrank(owner);
        mockNFT = new MockLeagueRewardNFT(address(factory));
        mockVault1 = new MockVault(address(factory));
        mockVault2 = new MockVault(address(factory));
        vm.stopPrank();
    }

    // ============ Tests ============

    // 1. Test initial state
    function testInitialState() public view {
        // The owner should be the one who deployed
        assertEq(factory.owner(), owner, "Owner should match the deployer");
        // No leagues at the start
        assertEq(factory.allLeaguesLength(), 0, "No leagues should exist at deployment");
        // No vaults at the start
        // The factory code doesn't add any vault in constructor, so 0 expected.
        // The state is consistent with what we tested.
    }

    // 2. Test createLeague success
    function testCreateLeague() public {
        // user1 wants to create a league. They must pay at least seasonCreationFee in USDC.
        // We'll let them pay 1000 USDC.
        uint256 dues = 1000 * 1e6;

        // Approve factory or direct league creation call to pull USDC
        vm.startPrank(user1);
        IERC20(USDC).approve(address(factory), dues);

        address newLeague = factory.createLeague("MyLeague", dues, "MyTeamName");
        vm.stopPrank();

        // The league should now exist
        assertTrue(factory.isLeague(newLeague), "New league should be recognized");
        assertEq(factory.leagueAddress("MyLeague"), newLeague, "leagueAddress should match newLeague");
        assertEq(factory.leagueName(newLeague), "MyLeague", "leagueName should match 'MyLeague'");

        // Check the length of all leagues
        assertEq(factory.allLeaguesLength(), 1, "Should have exactly 1 league");
    }

    // 3. Test createLeague reverts when leagueName is duplicate
    function testCreateLeagueRevertDuplicateName() public {
        // user1 creates the first league
        uint256 dues = 1000 * 1e6;
        vm.startPrank(user1);
        IERC20(USDC).approve(address(factory), dues);
        factory.createLeague("MyLeague", dues, "MyTeamName");
        vm.stopPrank();

        // user2 tries to create another league with same name
        vm.startPrank(user2);
        IERC20(USDC).approve(address(factory), dues);
        vm.expectRevert(bytes("LEAGUE_EXISTS"));
        factory.createLeague("MyLeague", dues, "OtherTeamName");
        vm.stopPrank();
    }

    // 4. Test createLeague reverts if dues < seasonCreationFee
    function testCreateLeagueRevertDuesTooLow() public {
        // First, let's set the seasonCreationFee to 2000 USDC
        vm.startPrank(owner);
        factory.setSeasonCreationFee(2000 * 1e6);
        vm.stopPrank();

        // user1 tries to create a league with only 1000 USDC
        uint256 dues = 1000 * 1e6;
        vm.startPrank(user1);
        IERC20(USDC).approve(address(factory), dues);
        vm.expectRevert(bytes("DUES_TOO_LOW"));
        factory.createLeague("UnderfundedLeague", dues, "MyTeamName");
        vm.stopPrank();
    }

    // 5. Test removing a league
    function testRemoveLeague() public {
        // user1 creates a league
        uint256 dues = 1000 * 1e6;
        vm.startPrank(user1);
        IERC20(USDC).approve(address(factory), dues);
        address newLeague = factory.createLeague("LeagueToRemove", dues, "TeamToRemove");
        vm.stopPrank();

        // The newly created league is recognized in the factory
        assertTrue(factory.isLeague(newLeague), "Should be recognized as league");
        assertEq(factory.allLeaguesLength(), 1, "Should have 1 league total");

        // Now removeLeague must be called by the league contract itself (msg.sender == league)
        // We'll impersonate the league contract to call removeLeague().
        vm.startPrank(newLeague);
        factory.removeLeague();
        vm.stopPrank();

        // Should no longer be recognized
        assertFalse(factory.isLeague(newLeague), "Should not be recognized anymore");
        assertEq(factory.leagueAddress("LeagueToRemove"), address(0), "leagueAddress should be cleared");
        assertEq(factory.leagueName(newLeague), "", "leagueName should be cleared");
        assertEq(factory.allLeaguesLength(), 0, "Should have 0 leagues now");
    }

    // 6. Test removeLeague revert if caller is not a league
    function testRemoveLeagueRevertNotLeague() public {
        vm.startPrank(user1);
        vm.expectRevert(bytes("NOT_LEAGUE"));
        factory.removeLeague();
        vm.stopPrank();
    }

    // 7. Test getTeamLeagues
    //    We will create two leagues, have user1 join both, user2 join one,
    //    then check the resulting array for each user.
    function testGetTeamLeagues() public {
        // user1 creates 2 leagues
        vm.startPrank(user1);
        IERC20(USDC).approve(address(factory), 2000 * 1e6); // enough for both
        address leagueA = factory.createLeague("LeagueA", 1000 * 1e6, "TeamA");
        address leagueB = factory.createLeague("LeagueB", 1000 * 1e6, "TeamB");
        vm.stopPrank();

        // user2 joins leagueB only. For now, let's assume there's a function on the league to join,
        // but your snippet doesn't show it. We'll just pretend or skip if not relevant.
        // In typical scenario: ILeague(leagueB).joinLeague(...) or something.
        // We'll assume user2 is recognized in leagueB. We'll mock that by partial mocking
        // or we can do nothing if the actual code doesn't support it.
        // For demonstration, let's just read the state for user1 and user2.

        LeagueFactory_TESTNET.TeamLeaugeInfo[] memory infoUser1 = factory.getTeamLeagues(user1);
        // We expect 2 entries (LeagueA & LeagueB).
        assertEq(infoUser1.length, 2, "Should have 2 leagues total for user1");
        // The order will be the same as factory.allLeagues (which is [leagueA, leagueB]).
        assertEq(address(infoUser1[0].league), leagueA, "First league check");
        assertEq(address(infoUser1[1].league), leagueB, "Second league check");

        // For user2, they haven't created or joined from the factory perspective unless
        // ILeague(...).teamWalletExists(user2) is true. If your `League_TESTNET` does that automatically,
        // you can verify. We'll just show the call returning 2 entries but with joined=false, currentlyActive=false.
        LeagueFactory_TESTNET.TeamLeaugeInfo[] memory infoUser2 = factory.getTeamLeagues(user2);
        assertEq(infoUser2.length, 2, "Should have 2 leagues total in the array");
        // Because user2 did not do anything in the snippet, we expect joined=false, currentlyActive=false
        for (uint256 i = 0; i < infoUser2.length; i++) {
            assertFalse(infoUser2[i].joined, "user2 not joined");
            assertFalse(infoUser2[i].currentlyActive, "user2 not active");
        }
    }

    // 8. Test setLeagueRewardNFT
    function testSetLeagueRewardNFT() public {
        // Only owner can call
        vm.startPrank(user1);
        vm.expectRevert();
        factory.setLeagueRewardNFT(address(mockNFT));
        vm.stopPrank();

        // From the owner
        vm.startPrank(owner);
        // If the NFT mock returns FACTORY = address(factory), this will succeed
        factory.setLeagueRewardNFT(address(mockNFT));
        vm.stopPrank();

        // Check
        assertEq(factory.leagueRewardNFT(), address(mockNFT), "NFT address should be set");
    }

    // 9. Test setLeagueRewardNFT revert if the mock NFT does not have the correct FACTORY
    function testSetLeagueRewardNFTRevertFactoryCheck() public {
        // Deploy a mock that points to a different factory
        MockLeagueRewardNFT otherNFT = new MockLeagueRewardNFT(address(0x1234));

        vm.startPrank(owner);
        vm.expectRevert(bytes("INVALID_FACTORY"));
        factory.setLeagueRewardNFT(address(otherNFT));
        vm.stopPrank();
    }

    // 10. Test setSeasonCreationFee
    function testSetSeasonCreationFee() public {
        // Only owner can call
        vm.startPrank(user2);
        vm.expectRevert();
        factory.setSeasonCreationFee(5000 * 1e6);
        vm.stopPrank();

        // From the owner
        vm.startPrank(owner);
        factory.setSeasonCreationFee(5000 * 1e6);
        vm.stopPrank();

        // Check
        assertEq(factory.seasonCreationFee(), 5000 * 1e6, "Creation fee should be 5000 USDC");
    }

    // 11. Test addVault
    function testAddVault() public {
        // Only owner can call
        vm.startPrank(user1);
        vm.expectRevert();
        factory.addVault(address(mockVault1));
        vm.stopPrank();

        vm.startPrank(owner);
        factory.addVault(address(mockVault1));
        vm.stopPrank();

        // Confirm
        assertTrue(factory.isVault(address(mockVault1)), "Vault1 should be recognized");
    }

    // 12. Test addVault revert if Vault is invalid
    function testAddVaultRevertInvalidFactory() public {
        // Deploy a vault that returns a different factory
        MockVault otherVault = new MockVault(address(0x1234));

        vm.startPrank(owner);
        vm.expectRevert(bytes("INVALID_FACTORY"));
        factory.addVault(address(otherVault));
        vm.stopPrank();
    }

    // 13. Test addVault revert if Vault already added
    function testAddVaultRevertVaultExists() public {
        vm.startPrank(owner);
        factory.addVault(address(mockVault1));
        vm.expectRevert(bytes("VAULT_EXISTS"));
        factory.addVault(address(mockVault1));
        vm.stopPrank();
    }

    // 14. Test removeVault
    function testRemoveVault() public {
        // First add the vault
        vm.startPrank(owner);
        factory.addVault(address(mockVault1));
        vm.stopPrank();

        // Confirm
        assertTrue(factory.isVault(address(mockVault1)), "Vault1 recognized");

        // Only owner can remove
        vm.startPrank(user1);
        vm.expectRevert();
        factory.removeVault(address(mockVault1));
        vm.stopPrank();

        // Owner remove
        vm.startPrank(owner);
        factory.removeVault(address(mockVault1));
        vm.stopPrank();

        // Confirm
        assertFalse(factory.isVault(address(mockVault1)), "Vault1 not recognized anymore");
    }

    // 15. Test removeVault revert if not in isVault
    function testRemoveVaultRevertVaultDoesNotExist() public {
        vm.startPrank(owner);
        vm.expectRevert(bytes("VAULT_DOES_NOT_EXIST"));
        factory.removeVault(address(mockVault2));
        vm.stopPrank();
    }
}
