// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/LeagueFactory_TESTNET.sol";

/**
 * @title DeployLeagueFactory
 * @notice A simple Foundry script to deploy the LeagueFactory_TESTNET contract.
 *
 * To run:
 *    forge script script/DeployLeagueFactory.s.sol \
 *       --rpc-url <YOUR_RPC_URL> \
 *       --private-key <YOUR_DEPLOYER_PRIVATE_KEY> \
 *       --broadcast
 */
contract DeployLeagueFactory is Script {
    function run() external {
        // 1. Load your deployer's private key from an environment variable or directly.
        //    E.g. "PRIVATE_KEY" from your shell environment (recommended).
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 2. Start broadcasting (publishing) transactions using the loaded private key.
        vm.startBroadcast(deployerPrivateKey);

        // 3. Deploy the contract.
        LeagueFactory_TESTNET factory = new LeagueFactory_TESTNET();

        // 4. Log the factory’s deployed address for easy reference.
        console.log("LeagueFactory_TESTNET deployed at:", address(factory));

        // 5. Stop broadcasting.
        vm.stopBroadcast();
    }
}
