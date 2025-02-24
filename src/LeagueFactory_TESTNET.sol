// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./League_TESTNET.sol";
import "./interfaces/ILeague.sol";
import "./interfaces/ILeagueRewardNFT.sol";

contract LeagueFactory_TESTNET is Ownable {
    address public constant USDC = address(0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B); // Testnet address
    address public leagueRewardNFT;
    bool public constant isFactory = true;
    mapping(string => address) public leagueAddress;
    mapping(address => string) public leagueName;
    mapping(address => bool) public isLeague;
    address[] public allLeagues;

    event LeagueCreated(string name, address league);
    event LeagueRemoved(string name, address league);

    constructor() Ownable(msg.sender) {}

    function allLeaguesLength() external view returns (uint256) {
        return allLeagues.length;
    }

    function createLeague(string memory _leagueName, uint256 _dues, string memory _teamName) external returns (address league) {
        require(leagueAddress[_leagueName] == address(0), "LEAGUE_EXISTS");
        League_TESTNET leagueContract = new League_TESTNET(_leagueName, _dues, _teamName, msg.sender);
        league = address(leagueContract);
        IERC20(USDC).transferFrom(msg.sender, league, _dues);
        leagueAddress[_leagueName] = league;
        leagueName[league] = _leagueName;
        isLeague[league] = true;
        allLeagues.push(league);
        emit LeagueCreated(_leagueName, league);
    }

    function removeLeague() external {
        require(isLeague[msg.sender], "NOT_LEAGUE");
        emit LeagueRemoved(leagueName[msg.sender], msg.sender);
        delete leagueAddress[leagueName[msg.sender]];
        delete leagueName[msg.sender];
        isLeague[msg.sender] = false;
        for (uint256 i = 0; i < allLeagues.length; i++) {
            if (allLeagues[i] == msg.sender) {
                allLeagues[i] = allLeagues[allLeagues.length - 1];
                allLeagues.pop();
                break;
            }
        }
    }

    function getActiveLeagues(address _team) external view returns (address[] memory) {
        uint256 count = 0;
        // First loop: count how many leagues are active
        for (uint256 i = 0; i < allLeagues.length; i++) {
            if (ILeague(allLeagues[i]).isTeamActive(_team)) {
                count++;
            }
        }

        // Allocate a memory array of the correct size
        address[] memory activeLeagues = new address[](count);

        // Second loop: populate the array
        uint256 index = 0;
        for (uint256 i = 0; i < allLeagues.length; i++) {
            if (ILeague(allLeagues[i]).isTeamActive(_team)) {
                activeLeagues[index] = allLeagues[i];
                index++;
            }
        }
        return activeLeagues;
    }

    function setLeagueRewardNFT(address _leagueRewardNFT) external onlyOwner {
        require(ILeagueRewardNFT(_leagueRewardNFT).FACTORY() == address(this), "INVALID_FACTORY");
        leagueRewardNFT = _leagueRewardNFT;
    }
}
