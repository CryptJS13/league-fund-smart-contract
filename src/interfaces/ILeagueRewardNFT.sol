// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/**
 * @title ILeagueRewardNFT
 * @notice Interface for the LeagueRewardNFT contract, focusing on the custom
 *         methods and public state. Standard ERC721 methods come from IERC721.
 */
interface ILeagueRewardNFT {
    /**
     * @dev Returns the factory address that deployed this contract.
     */
    function FACTORY() external view returns (address);

    /**
     * @notice Mint a new Reward NFT
     * @param _to          Recipient of the NFT
     * @param _leagueName  Name of the league (e.g. "Fantasy Football League")
     * @param _teamName    Name of the team receiving the reward
     * @param _rewardName  Short name / identifier of the reward
     * @param _usdcAmount  Amount of USDC allocated, e.g. 100e6
     * @param _imageData   URL or IPFS link for the reward image/metadata
     * @return The newly minted token ID
     */
    function mintReward(
        address _to,
        string calldata _leagueName,
        string calldata _teamName,
        string calldata _rewardName,
        uint256 _usdcAmount,
        string calldata _imageData
    ) external returns (uint256);

    /**
     * @notice Returns the URI for a given token ID, following ERC721Metadata's tokenURI standard.
     * @param tokenId The token ID to query
     * @return A data:application/json;base64 URI containing the NFT metadata
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
