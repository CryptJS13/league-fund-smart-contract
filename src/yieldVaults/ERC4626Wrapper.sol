// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/ILeagueFactory.sol";

contract ERC4626Wrapper is ERC20, IERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC4626 public underlyingVault;
    address public FACTORY;

    modifier onlyLeague() {
        require(ILeagueFactory(FACTORY).isLeague(msg.sender), "NOT_LEAGUE");
        _;
    }

    constructor(IERC4626 _underlyingVault, address _factory)
        ERC20(
            string(abi.encodePacked("Wrapped_", _underlyingVault.symbol())),
            string(abi.encodePacked("w", _underlyingVault.symbol()))
        )
    {
        underlyingVault = _underlyingVault;
        require(ILeagueFactory(_factory).isFactory(), "NOT_FACTORY");
        FACTORY = _factory;
    }

    function decimals() public view override(ERC20, IERC20Metadata) returns (uint8) {
        return underlyingVault.decimals();
    }

    function asset() public view returns (address) {
        return underlyingVault.asset();
    }

    function totalAssets() public view returns (uint256) {
        return convertToAssets(underlyingVault.balanceOf(address(this)));
    }

    function convertToShares(uint256 _assets) public view returns (uint256) {
        return underlyingVault.convertToShares(_assets);
    }

    function convertToAssets(uint256 _shares) public view returns (uint256) {
        return underlyingVault.convertToAssets(_shares);
    }

    function _deposit(uint256 _assets, address _receiver, address _sender) internal returns (uint256) {
        require(_assets > 0, "Cannot deposit 0");
        require(_receiver != address(0), "receiver must be defined");

        IERC20(asset()).safeTransferFrom(_sender, address(this), _assets);
        IERC20(asset()).forceApprove(address(underlyingVault), _assets);
        uint256 shares = underlyingVault.deposit(_assets, address(this));
        _mint(_receiver, shares);

        // update the contribution amount for the beneficiary
        emit IERC4626.Deposit(_sender, _receiver, _assets, shares);
        return shares;
    }

    function maxDeposit(address receiver) public view returns (uint256) {
        return ILeagueFactory(FACTORY).isLeague(msg.sender) ? underlyingVault.maxDeposit(receiver) : 0;
    }

    function previewDeposit(uint256 _assets) public view returns (uint256) {
        return underlyingVault.previewDeposit(_assets);
    }

    function deposit(uint256 _assets, address _receiver) public nonReentrant onlyLeague returns (uint256) {
        return _deposit(_assets, _receiver, msg.sender);
    }

    function maxMint(address) public pure returns (uint256) {
        return 0;
    }

    function previewMint(uint256) public pure returns (uint256) {
        revert("Not implemented");
    }

    function mint(uint256, address) public pure returns (uint256) {
        revert("Not implemented");
    }

    function _redeem(uint256 _shares, address _receiver, address _owner, address _sender) internal returns (uint256) {
        require(totalSupply() > 0, "Vault has no shares");
        require(_shares > 0, "Cannot redeem 0");

        if (_sender != _owner) {
            uint256 currentAllowance = allowance(_owner, _sender);
            if (currentAllowance != uint256(type(uint256).max)) {
                require(currentAllowance >= _shares, "ERC20: transfer amount exceeds allowance");
                _approve(_owner, _sender, currentAllowance - _shares);
            }
        }

        uint256 assets = underlyingVault.redeem(_shares, address(this), address(this));

        _burn(_owner, _shares);
        IERC20(asset()).safeTransfer(_receiver, assets);

        // update the withdrawal amount for the holder
        emit Withdraw(_sender, _receiver, _owner, assets, _shares);
        return assets;
    }

    function maxWithdraw(address) public pure returns (uint256) {
        return 0;
    }

    function previewWithdraw(uint256) public pure returns (uint256) {
        revert("Not implemented");
    }

    function withdraw(uint256, address, address) public pure returns (uint256) {
        revert("Not implemented");
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return underlyingVault.maxRedeem(owner);
    }

    function previewRedeem(uint256 _shares) public view returns (uint256) {
        return underlyingVault.previewRedeem(_shares);
    }

    function redeem(uint256 _shares, address _receiver, address _owner) public nonReentrant onlyLeague returns (uint256) {
        return _redeem(_shares, _receiver, _owner, msg.sender);
    }
}
