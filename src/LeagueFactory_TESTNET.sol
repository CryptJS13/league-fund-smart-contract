// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./League_TESTNET.sol";
import "./interfaces/ILeague.sol";
import "./interfaces/ILeagueRewardNFT.sol";
import "./interfaces/IVault.sol";

contract LeagueFactory_TESTNET is Ownable {
    bool public constant isFactory = true;
    address public constant USDC = address(0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B); // Testnet address

    event LeagueCreated(string name, address league);
    event LeagueRemoved(string name, address league);
    event SetLeagueRewardNFT(address leagueRewardNFT);
    event SetSeasonCreationFee(uint256 fee);
    event VaultAdded(address vault);
    event VaultRemoved(address vault);

    address public leagueRewardNFT;
    mapping(string => address) public leagueAddress;
    mapping(address => string) public leagueName;
    mapping(address => bool) public isLeague;
    address[] public allLeagues;

    mapping(address => bool) public isVault;
    address[] public allVaults;

    uint256 public seasonCreationFee = 0;

    struct TeamLeaugeInfo {
        string leagueName;
        address leagueAddress;
        bool joined;
        bool currentlyActive;
    }

    constructor() Ownable(msg.sender) {}

    function allLeaguesLength() external view returns (uint256) {
        return allLeagues.length;
    }

    function createLeague(string memory _leagueName, uint256 _dues, string memory _teamName) external returns (address league) {
        require(leagueAddress[_leagueName] == address(0), "LEAGUE_EXISTS");
        require(_dues >= seasonCreationFee, "DUES_TOO_LOW");
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

    function getTeamLeagues(address _team) external view returns (TeamLeaugeInfo[] memory) {
        TeamLeaugeInfo[] memory teamLeagues = new TeamLeaugeInfo[](allLeagues.length);

        for (uint256 i = 0; i < allLeagues.length; i++) {
            teamLeagues[i] = TeamLeaugeInfo({
                leagueName: leagueName[allLeagues[i]],
                leagueAddress: allLeagues[i],
                joined: ILeague(allLeagues[i]).teamWalletExists(_team),
                currentlyActive: ILeague(allLeagues[i]).isTeamActive(_team)
            });
        }
        return teamLeagues;
    }

    function setLeagueRewardNFT(address _leagueRewardNFT) external onlyOwner {
        require(ILeagueRewardNFT(_leagueRewardNFT).FACTORY() == address(this), "INVALID_FACTORY");
        leagueRewardNFT = _leagueRewardNFT;
        emit SetLeagueRewardNFT(_leagueRewardNFT);
    }

    function setSeasonCreationFee(uint256 _fee) external onlyOwner {
        seasonCreationFee = _fee;
        emit SetSeasonCreationFee(_fee);
    }

    function addVault(address _vault) external onlyOwner {
        require(IVault(_vault).FACTORY() == address(this), "INVALID_FACTORY");
        require(!isVault[_vault], "VAULT_EXISTS");
        isVault[_vault] = true;
        allVaults.push(_vault);
        emit VaultAdded(_vault);
    }

    function removeVault(address _vault) external onlyOwner {
        require(isVault[_vault], "VAULT_DOES_NOT_EXIST");
        isVault[_vault] = false;
        for (uint256 i = 0; i < allVaults.length; i++) {
            if (allVaults[i] == _vault) {
                allVaults[i] = allVaults[allVaults.length - 1];
                allVaults.pop();
                break;
            }
        }
        emit VaultRemoved(_vault);
    }
}
