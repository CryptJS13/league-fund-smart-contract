// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./interfaces/ILeagueFactory.sol";

/**
 * @title RewardNFT
 * @notice An ERC721 NFT that represents a reward allocation.
 *         Each NFT includes metadata with a "reward name", USDC amount,
 *         and an image (either on-chain SVG or off-chain URL).
 */
contract LeagueRewardNFT_TESTNET is ERC721 {
    using Strings for uint256;

    /**
     * @dev For each token, we store:
     *      - leagueName:  e.g., "Fantasy Football League"
     *      - teamName:    e.g., "Team Awesome"
     *      - rewardName:  e.g., "Top Scorer Reward"
     *      - usdcAmount:  e.g., 100e6 (for 100 USDC)
     *      - imageData:   either an SVG or a URI pointer to an image
     *      - isOnChain:   if true => imageData holds on-chain SVG (base64-encoded or plain text)
     *                     if false => imageData is a URI to an off-chain image
     */
    struct RewardInfo {
        string leagueName;
        string teamName;
        string rewardName;
        uint256 usdcAmount;
        string imageData;
    }

    address public FACTORY;

    // TokenID -> RewardInfo
    mapping(uint256 => RewardInfo) private _rewards;

    // Auto-incremented token ID
    uint256 private _currentTokenId;

    modifier onlyLeague() {
        require(ILeagueFactory(FACTORY).isLeague(msg.sender), "NOT_LEAGUE");
        _;
    }

    constructor(string memory _name, string memory _symbol, address _factory) ERC721(_name, _symbol) {
        FACTORY = _factory;
    }

    /**
     * @notice Mint a new Reward NFT
     * @param _to          Recipient of the NFT
     * @param _rewardName  Short name / identifier of the reward
     * @param _usdcAmount  Amount of USDC allocated, e.g. 100e6
     * @param _imageData   This is a URL or IPFS link
     */
    function mintReward(
        address _to,
        string memory _leagueName,
        string memory _teamName,
        string memory _rewardName,
        uint256 _usdcAmount,
        string memory _imageData
    ) external onlyLeague returns (uint256) {
        _currentTokenId++;
        uint256 newTokenId = _currentTokenId;

        _rewards[newTokenId] = RewardInfo({
            leagueName: _leagueName,
            teamName: _teamName,
            rewardName: _rewardName,
            usdcAmount: _usdcAmount,
            imageData: _imageData
        });

        _safeMint(_to, newTokenId);

        return newTokenId;
    }

    /**
     * @notice Returns the on-chain metadata as a base64-encoded JSON string
     *         if `isOnChain` is true, we embed the image in "image" or "image_data" field.
     *         Otherwise, we set "image" to be the off-chain URL.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        RewardInfo memory info = _rewards[tokenId];

        return _buildMetadata(info);
    }

    /**
     * @dev Builds a JSON with fields for rewardName, usdcAmount, image = info.imageData, etc.
     */
    function _buildMetadata(RewardInfo memory info) private pure returns (string memory) {
        bytes memory json = abi.encodePacked(
            "{",
            '"name":"',
            info.rewardName,
            '",',
            '"description":"Reward NFT to Team: ',
            info.teamName,
            " in League: ",
            info.leagueName,
            '",',
            '"attributes": [',
            '{"trait_type": "USDC Amount", "value":"',
            (info.usdcAmount / 1e6).toString(),
            '"}',
            "],",
            '"image":"',
            info.imageData,
            '"',
            "}"
        );

        return _encodeJson(json);
    }

    /**
     * @dev Helper function to do data:application/json;base64 encoding
     */
    function _encodeJson(bytes memory json) private pure returns (string memory) {
        string memory encodedJson = Base64.encode(json);
        return string(abi.encodePacked("data:application/json;base64,", encodedJson));
    }
}
