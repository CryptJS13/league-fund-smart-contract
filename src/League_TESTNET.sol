// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract League_TESTNET is AccessControl {
    bytes32 public constant COMMISSIONER_ROLE = keccak256("COMMISSIONER_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");
    address public constant USDC = address(0xa2fc8C407E0Ab497ddA623f5E16E320C7c90C83B); // Testnet address

    struct SeasonData {
        string name;
        uint256 dues;
        address[] teams;
    }

    struct TeamData {
        string name;
        address wallet;
    }

    string public name;
    SeasonData[] public seasons;
    TeamData[] public allTeams;

    mapping(string => bool) public seasonExists;
    mapping(string => bool) public teamExists;
    mapping(address => string) public teamName;

    constructor(
        string memory _leagueName,
        address _commissioner,
        string memory _seasonName,
        uint256 _dues,
        string memory _teamName
    ) {
        _setRoleAdmin(TREASURER_ROLE, COMMISSIONER_ROLE);
        _setRoleAdmin(COMMISSIONER_ROLE, COMMISSIONER_ROLE);
        _grantRole(COMMISSIONER_ROLE, _commissioner);
        _grantRole(TREASURER_ROLE, _commissioner);
        name = _leagueName;

        initLeague(_seasonName, _dues, _teamName, _commissioner);
    }

    function initLeague(string memory _seasonName, uint256 _dues, string memory _teamName, address _commissioner) private {
        require(seasons.length == 0, "INITIALIZED");
        seasonExists[_seasonName] = true;
        seasons.push(SeasonData({name: _seasonName, dues: _dues, teams: new address[](0)}));
        teamExists[_teamName] = true;
        teamName[_commissioner] = _teamName;
        seasons[0].teams.push(_commissioner);
        allTeams.push(TeamData({name: _teamName, wallet: _commissioner}));
    }

    function currentSeason() public view returns (SeasonData memory) {
        return seasons[seasons.length - 1];
    }

    function activeTeams() public view returns (TeamData[] memory) {
        address[] memory teams = currentSeason().teams;
        TeamData[] memory _activeTeams = new TeamData[](teams.length);
        for (uint256 i = 0; i < teams.length; i++) {
            address team = teams[i];
            _activeTeams[i] = TeamData({name: teamName[team], wallet: team});
        }
        return _activeTeams;
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

    function createSeason(string memory _name, uint256 _dues) public onlyRole(COMMISSIONER_ROLE) {
        require(!seasonExists[_name], "SEASON_EXISTS");
        seasonExists[_name] = true;
        seasons.push(SeasonData({name: _name, dues: _dues, teams: new address[](0)}));
    }

    function joinSeason(string memory _teamName) public {
        require(!teamExists[_teamName], "TEAM_EXISTS");
        teamExists[_teamName] = true;
        teamName[msg.sender] = _teamName;
        IERC20(USDC).transferFrom(msg.sender, address(this), currentSeason().dues);
        seasons[seasons.length - 1].teams.push(msg.sender);
        allTeams.push(TeamData({name: _teamName, wallet: msg.sender}));
    }
}
