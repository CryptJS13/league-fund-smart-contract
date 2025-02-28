// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/IAccessControl.sol";

interface ILeague is IAccessControl {
    // Roles
    function COMMISSIONER_ROLE() external pure returns (bytes32);
    function TREASURER_ROLE() external pure returns (bytes32);

    // Constants
    function USDC() external pure returns (address);
    function FACTORY() external view returns (address);

    // Public storage variables
    function name() external view returns (string memory);

    // The seasons array is public, so its getter is:
    // function seasons(uint256) external view returns (uint256 dues, address[] memory teams);
    // But to replicate that in an interface, do:
    function seasons(uint256 index) external view returns (uint256, address[] memory);

    // The allTeams array is public: function allTeams(uint256) external view returns (address);
    function allTeams(uint256 index) external view returns (address);

    // Mappings
    function teamNameExists(string calldata teamName) external view returns (bool);
    function teamWalletExists(address teamWallet) external view returns (bool);
    function teamName(address teamWallet) external view returns (string memory);

    // Struct definitions (needed for the functions that return these types)
    struct SeasonData {
        uint256 dues;
        address[] teams;
    }

    struct TeamData {
        string name;
        address wallet;
    }

    // External/public functions
    function leagueBalance() external view returns (uint256);

    // Returning a struct with a dynamic array can require viaIR; if you get compiler errors,
    // you might remove or refactor this function from the interface.
    function currentSeason() external view returns (SeasonData memory);

    function getActiveTeams() external view returns (TeamData[] memory);
    function getAllTeams() external view returns (TeamData[] memory);

    function setCommissioner(address _commissioner) external;
    function addTreasurer(address _treasurer) external;
    function removeTreasurer(address _treasurer) external;
    function createSeason(uint256 _dues) external;
    function joinSeason(string calldata _teamName) external;
    function isTeamActive(address _team) external view returns (bool);
    function removeTeam(address _team) external;
    function closeLeague() external;

    function allocateReward(address _team, string calldata _rewardName, uint256 _rewardAmount) external;
    function claimReward(string calldata _imageURL) external;
}
