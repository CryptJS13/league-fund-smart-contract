// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

interface ILeagueFactory {
    // Events
    event LeagueCreated(string name, address league);
    event LeagueRemoved(string name, address league);

    // Public constant
    function USDC() external view returns (address);
    function owner() external view returns (address);
    function isFactory() external view returns (bool);
    function isLeague(address) external view returns (bool);
    function isVault(address) external view returns (bool);

    function leagueRewardNFT() external view returns (address);
    function setLeagueRewardNFT(address _leagueRewardNFT) external;

    function seasonCreationFee() external view returns (uint256);
    function setSeasonCreationFee(uint256 _fee) external;

    // Public mappings
    function leagueAddress(string calldata) external view returns (address);
    function leagueName(address) external view returns (string memory);

    // Public array getter (returns the address at a specific index)
    function allLeagues(uint256) external view returns (address);

    // External/public functions
    function allLeaguesLength() external view returns (uint256);

    function createLeague(string calldata _leagueName, uint256 _dues, string calldata _teamName)
        external
        returns (address league);

    function removeLeague() external;
}
