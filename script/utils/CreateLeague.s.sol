// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/interfaces/ILeagueFactory.sol";
import "../../addresses.sol";

/**
 * @title DeployLeagueFactory
 * @notice A simple Foundry script to deploy the LeagueFactory_TESTNET contract.
 *
 * To run:
 *    forge script script/utils/CreateLeague.s.sol \
 *       --rpc-url sepolia \
 *       --broadcast \
 *       --sig "run(string,uint256,string)" "MyLeague" 100000000 "MyTeam"
 */
contract CreateLeague is Script {
    function run(string memory leagueName, uint256 dues, string memory teamName) external {
        // 1. Load your deployer's private key from an environment variable or directly.
        //    E.g. "PRIVATE_KEY" from your shell environment (recommended).
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 2. Start broadcasting (publishing) transactions using the loaded private key.
        vm.startBroadcast(deployerPrivateKey);

        // 3. Approve USDC and create new League through the factory.
        IERC20(ADDRESSES.USDC).approve(ADDRESSES.LEAGUE_FACTORY, dues);
        address newLeague = ILeagueFactory(ADDRESSES.LEAGUE_FACTORY).createLeague(leagueName, dues, teamName);

        console.log("New League deployed at:", newLeague);

        // 4. Stop broadcasting.
        vm.stopBroadcast();
    }
}
