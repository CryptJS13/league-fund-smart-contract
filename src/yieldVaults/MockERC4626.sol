// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title MockERC4626
 * @notice A basic mock of ERC4626 vault behavior:
 *         - Maintains an asset:share ratio using totalSupply() and the vault’s asset balance.
 *         - On deposit/mint, pulls ERC20 assets from user, mints shares.
 *         - On withdraw/redeem, burns shares, sends back the proportional assets.
 *
 *         This is for testing purposes only. Production vaults often have more checks,
 *         rounding logic, fee accounting, reentrancy guard, etc.
 */
contract MockERC4626 is ERC20, IERC4626 {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata public immutable assetToken; // The underlying asset
    uint8 private immutable _decimals; // Cache decimals for this vault

    constructor(IERC20Metadata _asset)
        ERC20(string(abi.encodePacked("Vault_", _asset.symbol())), string(abi.encodePacked("v", _asset.symbol())))
    {
        assetToken = _asset;
        _decimals = _asset.decimals();
    }

    /**
     * @dev For compatibility with ERC4626 vault shares, this vault’s decimals
     *      should match the underlying asset’s decimals, though it’s not strictly required.
     */
    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return _decimals;
    }

    // ------------------------------------------------
    // ERC4626-Required View Functions
    // ------------------------------------------------

    /**
     * @return The address of the underlying asset.
     */
    function asset() public view override returns (address) {
        return address(assetToken);
    }

    /**
     * @return The total amount of the underlying asset that is “managed” by this vault.
     */
    function totalAssets() public view override returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    /**
     * @dev Converts an amount of `assets` to the equivalent amount of `shares`,
     *      using the current ratio of totalSupply() to totalAssets().
     */
    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        uint256 assetBal = totalAssets();
        if (supply == 0 || assetBal == 0) {
            return assets; // 1:1 if no shares yet
        }
        return (assets * supply) / assetBal;
    }

    /**
     * @dev Converts an amount of `shares` to the equivalent amount of `assets`.
     */
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        uint256 assetBal = totalAssets();
        if (supply == 0 || assetBal == 0) {
            return shares; // 1:1 if no shares yet
        }
        return (shares * assetBal) / supply;
    }

    // ------------------------------------------------
    // ERC4626-Optional Limits
    // ------------------------------------------------

    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max; // no limit
    }

    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max; // no limit
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        // The user can only withdraw up to the assets that their shares represent
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        // The user can only redeem the shares they hold
        return balanceOf(owner);
    }

    // ------------------------------------------------
    // ERC4626-Preview Functions
    // ------------------------------------------------

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        // The assets needed is the inverse of convertToShares
        // So: assets = convertToAssets(shares)
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        // shares = convertToShares(assets)
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        // assets = convertToAssets(shares)
        return convertToAssets(shares);
    }

    // ------------------------------------------------
    // ERC4626 Core Mutative Functions
    // ------------------------------------------------

    /**
     * @dev Pulls `assets` from caller, mints `receiver` vault shares.
     *      Returns the amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        require(assets > 0, "Deposit must be > 0");

        // 1. Calculate shares
        uint256 shares = convertToShares(assets);

        // 2. Pull underlying asset from caller
        assetToken.safeTransferFrom(msg.sender, address(this), assets);

        // 3. Mint shares to receiver
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    /**
     * @dev Pulls enough assets from caller to mint exactly `shares` to `receiver`.
     *      Returns the actual assets pulled.
     */
    function mint(uint256 shares, address receiver) public override returns (uint256) {
        require(shares > 0, "Mint must be > 0");

        // 1. Calculate assets required
        uint256 assets = convertToAssets(shares);

        // 2. Pull assets
        assetToken.safeTransferFrom(msg.sender, address(this), assets);

        // 3. Mint shares
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
        return assets;
    }

    /**
     * @dev Burns `assets` worth of shares from `owner`, sends those assets to `receiver`.
     *      Returns shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        require(assets > 0, "Withdraw must be > 0");

        // 1. Calculate how many shares represent `assets`
        uint256 shares = convertToShares(assets);

        // 2. If caller != owner, check allowance
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // 3. Burn from owner
        _burn(owner, shares);

        // 4. Transfer assets to receiver
        assetToken.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    /**
     * @dev Burns `shares` from `owner`, sends out the corresponding assets to `receiver`.
     *      Returns assets sent.
     */
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        require(shares > 0, "Redeem must be > 0");

        // 1. If caller != owner, check allowance
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // 2. Calculate assets
        uint256 assets = convertToAssets(shares);

        // 3. Burn shares
        _burn(owner, shares);

        // 4. Transfer assets
        assetToken.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return assets;
    }
}
