// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Your contracts' imports (adjust as needed)
import "../src/LeagueFactory_TESTNET.sol";
import "../src/LeagueRewardNFT_TESTNET.sol";
import "../src/yieldVaults/MockERC4626.sol";
import "../src/yieldVaults/ERC4626Wrapper.sol";

/**
 * @title DeployAll
 * @notice Foundry script that:
 *         1) Deploys the factory.
 *         2) Deploys the rewardNFT and sets it to the factory.
 *         3) Deploys MockERC4626 on top of USDC (Sepolia address).
 *         4) Deploys ERC4626Wrapper on top of MockERC4626.
 *         5) Optionally sets the wrapper in the factory if needed.
 *         6) Deploys a League through the factory.
 *         If run with --verify, it also verifies source code on Etherscan.
 *
 * Usage:
 *    forge script script/DeployAll.s.sol \
 *      --rpc-url <URL> \
 *      --broadcast \
 *      --verify
 *
 * Make sure your foundry.toml has the correct etherscan config for "sepolia" or pass --etherscan-api-key.
 */
contract DeployAll is Script {
    // The USDC address on Sepolia (mock for demonstration).
    address internal constant SEPOLIA_USDC = 0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B;

    // Some basic parameters for the league
    string internal constant LEAGUE_NAME = "MyLeague";
    uint256 internal constant INITIAL_DUES = 100e6; // 100 USDC
    string internal constant INITIAL_TEAM_NAME = "CommishTeam";

    function run() external {
        // 1. Read private key from env (or pass --private-key on CLI)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 2. Start broadcasting => actual on-chain tx
        vm.startBroadcast(deployerPrivateKey);

        // ----------------------------------------------------------------
        // Deploy the factory
        // ----------------------------------------------------------------
        LeagueFactory_TESTNET factory = new LeagueFactory_TESTNET();
        console.log("Factory deployed at:", address(factory));

        // ----------------------------------------------------------------
        // Deploy reward NFT & set to factory
        // ----------------------------------------------------------------
        LeagueRewardNFT_TESTNET rewardNft = new LeagueRewardNFT_TESTNET("RewardNFT", "RWD", address(factory));
        console.log("Reward NFT deployed at:", address(rewardNft));

        // we set the reward NFT in the factory
        factory.setLeagueRewardNFT(address(rewardNft));
        console.log("Reward NFT set in factory");

        // ----------------------------------------------------------------
        // Deploy MockERC4626 referencing USDC
        // ----------------------------------------------------------------
        MockERC4626 mockVault = new MockERC4626(IERC20Metadata(SEPOLIA_USDC));
        console.log("MockERC4626 vault deployed at:", address(mockVault));

        // ----------------------------------------------------------------
        // Deploy ERC4626Wrapper referencing the mock vault
        // ----------------------------------------------------------------
        ERC4626Wrapper wrapper = new ERC4626Wrapper(
            mockVault, // underlyingVault
            address(factory) // FACTORY for isFactory() checks, if needed
        );
        console.log("ERC4626Wrapper deployed at:", address(wrapper));

        // we set the reward NFT in the factory
        factory.addVault(address(wrapper));
        console.log("Vault added to factory");

        // ----------------------------------------------------------------
        // Create a League via factory
        // ----------------------------------------------------------------
        // We'll impersonate or set some deployer as the "commissioner."
        // For demonstration, let's just do it from the same deployer address.
        // Need to approve USDC to the factory before calling createLeague
        // so let's do an ephemeral step:
        // The deployer has no USDC by default unless we've funded it,
        // but we'll do the approve anyway as a demonstration.

        // If you actually have USDC in this deployer account on-chain, or
        // you want to skip creating a league from the deployer, you can remove.
        IERC20(SEPOLIA_USDC).approve(address(factory), INITIAL_DUES);

        address leagueAddr = factory.createLeague(LEAGUE_NAME, INITIAL_DUES, INITIAL_TEAM_NAME);
        console.log("League deployed at:", leagueAddr);

        // 3. Stop broadcasting => no more real tx
        vm.stopBroadcast();

        // If run with `forge script ... --verify`, Foundry will attempt
        // to verify each contract that was deployed in "broadcasted" mode on Etherscan.
        // Make sure your foundry.toml or CLI includes Etherscan config for "sepolia".
    }
}
