// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/LeagueFactory_TESTNET.sol";
import "../src/League_TESTNET.sol";
import "../src/LeagueRewardNFT_TESTNET.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/ILeagueRewardNFT.sol";

/**
 * @dev This test suite assumes:
 * - You're forking a testnet (or local chain) where USDC exists at 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B
 * - A whale at 0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F can distribute USDC
 * - The rest is consistent with your prior tests (e.g., from LeagueTest.t.sol).
 */
contract LeagueRewardNFTTest is Test {
    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------
    address public constant USDC = 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B;
    address public constant whale = 0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F;

    // -----------------------------------------------------------------------
    // Test users
    // -----------------------------------------------------------------------
    address public owner = address(100);
    address public commissioner = address(101);
    address public user1 = address(102);

    // -----------------------------------------------------------------------
    // Contracts to be deployed
    // -----------------------------------------------------------------------
    LeagueFactory_TESTNET public factory;
    LeagueRewardNFT_TESTNET public rewardNFT;
    League_TESTNET public league;

    // -----------------------------------------------------------------------
    // Setup
    // -----------------------------------------------------------------------
    function setUp() public {
        vm.label(owner, "Owner");
        vm.label(commissioner, "Commissioner");
        vm.label(user1, "User1");
        vm.label(whale, "USDC_Whale");
        vm.label(USDC, "USDC");

        // Fund the whale with some ETH to pay gas if needed
        vm.deal(whale, 100 ether);

        // 1) Deploy factory from "owner"
        vm.startPrank(owner);
        factory = new LeagueFactory_TESTNET();
        vm.stopPrank();

        // 2) Deploy Reward NFT referencing the factory
        vm.startPrank(owner);
        rewardNFT = new LeagueRewardNFT_TESTNET("LeagueRewardNFT", "LRNFT", address(factory));
        vm.stopPrank();

        // 3) Set this NFT in the factory
        vm.startPrank(owner);
        factory.setLeagueRewardNFT(address(rewardNFT));
        vm.stopPrank();

        // Impersonate whale to give some USDC to our test users
        vm.startPrank(whale);
        IERC20(USDC).transfer(commissioner, 5000 * 1e6);
        IERC20(USDC).transfer(user1, 2000 * 1e6);
        vm.stopPrank();

        // 4) Commissioner creates a league through the factory
        vm.startPrank(commissioner);
        IERC20(USDC).approve(address(factory), 1000 * 1e6);
        address leagueAddr = factory.createLeague("TestLeague", 1000 * 1e6, "CommissionerTeam");
        vm.stopPrank();

        league = League_TESTNET(leagueAddr);
    }

    // -----------------------------------------------------------------------
    // 1. Test: only recognized leagues can call mintReward()
    // -----------------------------------------------------------------------
    function testMintRewardRevertNotLeague() public {
        // Attempt to call mintReward directly from user1 => revert "NOT_LEAGUE"
        vm.startPrank(user1);
        vm.expectRevert("NOT_LEAGUE");
        rewardNFT.mintReward(user1, "FakeLeagueName", "FakeTeamName", "FakeRewardName", 100 * 1e6, "ipfs://someImageHash");
        vm.stopPrank();
    }

    // -----------------------------------------------------------------------
    // 2. Test: successful mint by an actual league
    // -----------------------------------------------------------------------
    function testMintRewardSuccess() public {
        // We'll impersonate the league contract as the caller
        vm.startPrank(address(league));
        uint256 tokenId =
            rewardNFT.mintReward(user1, "TestLeague", "TeamUser1", "ChampionshipReward", 200 * 1e6, "ipfs://someImageURI");
        vm.stopPrank();

        // Check minted token: tokenId should be 1 if it's the first minted
        assertEq(tokenId, 1, "First minted token should have ID=1");

        // Check that user1 is now the owner
        assertEq(rewardNFT.ownerOf(tokenId), user1, "Owner is user1");
    }

    // -----------------------------------------------------------------------
    // 3. Test: tokenURI revert if token does not exist
    // -----------------------------------------------------------------------
    function testTokenURINonExistent() public {
        // No token minted yet => tokenID=1 does not exist
        vm.expectRevert();
        rewardNFT.tokenURI(1);
    }
}
