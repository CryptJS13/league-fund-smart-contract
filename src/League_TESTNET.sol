// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILeagueFactory.sol";
import "./interfaces/ILeagueRewardNFT.sol";

contract League_TESTNET is AccessControl {
    bytes32 public constant COMMISSIONER_ROLE = keccak256("COMMISSIONER_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");
    address public constant USDC = address(0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B); // Testnet address
    address public FACTORY;

    struct SeasonData {
        uint256 dues;
        address[] teams;
    }

    struct TeamData {
        string name;
        address wallet;
    }

    struct RewardData {
        string name;
        uint256 amount;
    }

    string public name;
    SeasonData[] public seasons;
    address[] public allTeams;
    mapping(address => RewardData[]) public teamRewards;
    uint256 public totalClaimableRewards;

    mapping(string => bool) public teamNameExists;
    mapping(address => bool) public teamWalletExists;
    mapping(address => string) public teamName;

    modifier onlyActive() {
        require(isActive(), "LEAGUE_NOT_ACTIVE");
        _;
    }

    constructor(string memory _leagueName, uint256 _dues, string memory _teamName, address _commissioner) {
        require(ILeagueFactory(msg.sender).isFactory(), "NOT_FACTORY");
        FACTORY = msg.sender;
        _setRoleAdmin(TREASURER_ROLE, COMMISSIONER_ROLE);
        _setRoleAdmin(COMMISSIONER_ROLE, COMMISSIONER_ROLE);
        _grantRole(COMMISSIONER_ROLE, _commissioner);
        _grantRole(TREASURER_ROLE, _commissioner);
        name = _leagueName;

        initLeague(_dues, _teamName, _commissioner);
    }

    function isActive() public view returns (bool) {
        if (FACTORY != address(0)) {
            return ILeagueFactory(FACTORY).isLeague(address(this));
        }
        return false;
    }

    function initLeague(uint256 _dues, string memory _teamName, address _commissioner) private {
        require(seasons.length == 0, "INITIALIZED");
        seasons.push(SeasonData({dues: _dues, teams: new address[](0)}));
        teamNameExists[_teamName] = true;
        teamWalletExists[_commissioner] = true;
        teamName[_commissioner] = _teamName;
        seasons[0].teams.push(_commissioner);
        allTeams.push(_commissioner);
    }

    function leagueBalance() public view returns (uint256) {
        return IERC20(USDC).balanceOf(address(this));
    }

    function currentSeason() public view returns (SeasonData memory) {
        return seasons[seasons.length - 1];
    }

    function getActiveTeams() public view returns (TeamData[] memory) {
        address[] memory teams = currentSeason().teams;
        TeamData[] memory _activeTeams = new TeamData[](teams.length);
        for (uint256 i = 0; i < teams.length; i++) {
            address team = teams[i];
            _activeTeams[i] = TeamData({name: teamName[team], wallet: team});
        }
        return _activeTeams;
    }

    function getAllTeams() public view returns (TeamData[] memory) {
        TeamData[] memory _allTeams = new TeamData[](allTeams.length);
        for (uint256 i = 0; i < allTeams.length; i++) {
            address team = allTeams[i];
            _allTeams[i] = TeamData({name: teamName[team], wallet: team});
        }
        return _allTeams;
    }

    function setCommissioner(address _commissioner) external onlyRole(COMMISSIONER_ROLE) {
        _grantRole(COMMISSIONER_ROLE, _commissioner);
        _revokeRole(COMMISSIONER_ROLE, msg.sender);
    }

    function addTreasurer(address _treasurer) external onlyRole(COMMISSIONER_ROLE) {
        _grantRole(TREASURER_ROLE, _treasurer);
    }

    function removeTreasurer(address _treasurer) external onlyRole(COMMISSIONER_ROLE) {
        _revokeRole(TREASURER_ROLE, _treasurer);
    }

    function createSeason(uint256 _dues) public onlyRole(COMMISSIONER_ROLE) {
        seasons.push(SeasonData({dues: _dues, teams: new address[](0)}));
    }

    function joinSeason(string memory _teamName) public onlyActive {
        require(!teamNameExists[_teamName], "TEAM_NAME_EXISTS");
        require(!teamWalletExists[msg.sender], "TEAM_WALLET_EXISTS");
        teamNameExists[_teamName] = true;
        teamWalletExists[msg.sender] = true;
        teamName[msg.sender] = _teamName;
        IERC20(USDC).transferFrom(msg.sender, address(this), currentSeason().dues);
        seasons[seasons.length - 1].teams.push(msg.sender);
        allTeams.push(msg.sender);
    }

    function isTeamActive(address _team) public view returns (bool) {
        address[] memory teams = currentSeason().teams;
        for (uint256 i = 0; i < teams.length; i++) {
            if (teams[i] == _team) {
                return true;
            }
        }
        return false;
    }

    function removeTeam(address _team) external onlyRole(COMMISSIONER_ROLE) {
        require(isTeamActive(_team), "TEAM_NOT_IN_SEASON");
        address[] storage seasonTeams = seasons[seasons.length - 1].teams;
        for (uint256 i = 0; i < seasonTeams.length; i++) {
            if (seasonTeams[i] == _team) {
                seasonTeams[i] = seasonTeams[seasonTeams.length - 1];
                seasonTeams.pop();
                IERC20(USDC).transfer(_team, currentSeason().dues);
                break;
            }
        }
    }

    function closeLeague() external onlyRole(COMMISSIONER_ROLE) {
        createSeason(0);
        IERC20(USDC).transfer(msg.sender, IERC20(USDC).balanceOf(address(this)));
        ILeagueFactory(FACTORY).removeLeague();
    }

    function allocateReward(address _team, string memory _name, uint256 _amount) external onlyRole(COMMISSIONER_ROLE) {
        require(isTeamActive(_team), "TEAM_NOT_IN_SEASON");
        totalClaimableRewards += _amount;
        require(totalClaimableRewards <= leagueBalance(), "INSUFFICIENT_BALANCE");
        teamRewards[_team].push(RewardData({name: _name, amount: _amount}));
    }

    function claimReward(string memory imageURL) external {
        uint256 totalRewards = 0;
        RewardData[] storage rewards = teamRewards[msg.sender];
        for (uint256 i = 0; i < rewards.length; i++) {
            ILeagueRewardNFT(ILeagueFactory(FACTORY).leagueRewardNFT()).mintReward(
                msg.sender, name, teamName[msg.sender], rewards[i].name, rewards[i].amount, imageURL
            );
            totalRewards += rewards[i].amount;
        }
        delete teamRewards[msg.sender];
        if (totalRewards > 0) {
            totalClaimableRewards -= totalRewards;
            IERC20(USDC).transfer(msg.sender, totalRewards);
        }
    }
}
