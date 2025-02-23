// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./League_TESTNET.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LeagueFactory_TESTNET {
    address public constant USDC = address(0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B); // Testnet address
    mapping(string => address) public getLeague;
    address[] public allLeagues;

    event League(string name, address league);

    function allLeaguesLength() external view returns (uint256) {
        return allLeagues.length;
    }

    function createLeague(string memory _leagueName, string memory _seasonName, uint256 _dues, string memory _teamName)
        external
        returns (address league)
    {
        require(getLeague[_leagueName] == address(0), "LEAGUE_EXISTS");
        League_TESTNET leagueContract = new League_TESTNET(_leagueName, msg.sender, _seasonName, _dues, _teamName);
        league = address(leagueContract);
        IERC20(USDC).transferFrom(msg.sender, league, _dues);
        getLeague[_leagueName] = league;
        allLeagues.push(league);
    }
}
