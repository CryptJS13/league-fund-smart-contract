// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/interfaces/ILeague.sol";
import "../../addresses.sol";

/**
 * @title DeployLeagueFactory
 * @notice A simple Foundry script to deploy the LeagueFactory_TESTNET contract.
 *
 * To run:
 *    forge script script/utils/AllocateReward.s.sol \
 *       --rpc-url sepolia \
 *       --broadcast \
 *       --sig "run(address,address,string,uint256)" 0x59598c408485108FeBD06a81f36d8078f01Df230 0xE262C1e7c5177E28E51A5cf1C6944470697B2c9F "New Reward Name" 10000000
 */
contract AllocateReward is Script {
    function run(address league, address teamAddress, string memory rewardName, uint256 rewardAmount) external {
        // 1. Load your deployer's private key from an environment variable or directly.
        //    E.g. "PRIVATE_KEY" from your shell environment (recommended).
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 2. Start broadcasting (publishing) transactions using the loaded private key.
        vm.startBroadcast(deployerPrivateKey);

        // 3. Approving USDC and starting new Season on League.
        ILeague(league).allocateReward(teamAddress, rewardName, rewardAmount);

        console.log("Allocated reward to:", teamAddress);

        // 4. Stop broadcasting.
        vm.stopBroadcast();
    }
}
