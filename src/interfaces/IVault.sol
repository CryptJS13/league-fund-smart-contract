// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IVault {
    // State variables (with their auto-generated getters)
    function underlyingVault() external view returns (address);
    function FACTORY() external view returns (address);

    // Overridden from ERC20 / IERC4626
    function decimals() external view returns (uint8);

    // ERC4626: asset / totalAssets / convertToShares / convertToAssets
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function convertToShares(uint256 _assets) external view returns (uint256);
    function convertToAssets(uint256 _shares) external view returns (uint256);

    // ERC4626 deposit-related functions
    function maxDeposit(address receiver) external view returns (uint256);
    function previewDeposit(uint256 _assets) external view returns (uint256);
    function deposit(uint256 _assets, address _receiver) external returns (uint256);

    // ERC4626 redeem-related functions
    function maxRedeem(address owner) external view returns (uint256);
    function previewRedeem(uint256 _shares) external view returns (uint256);
    function redeem(uint256 _shares, address _receiver, address _owner) external returns (uint256);

    // The standard IERC4626 events:
    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
}
