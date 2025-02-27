// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./interfaces/ILeagueFactory.sol";
import "./interfaces/ILeagueRewardNFT.sol";

contract League_TESTNET is AccessControl {
    using SafeERC20 for IERC20;

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

    event LeagueInitialized(string leagueName, address commissioner, uint256 initialDues);
    event SeasonCreated(uint256 indexed seasonIndex, uint256 dues);
    event JoinedSeason(address indexed teamWallet, string teamName, uint256 seasonIndex);
    event TeamRemoved(address indexed teamWallet, uint256 seasonIndex);
    event CommissionerChanged(address indexed oldCommissioner, address indexed newCommissioner);
    event TreasurerAdded(address indexed newTreasurer);
    event TreasurerRemoved(address indexed oldTreasurer);
    event RewardAllocated(address indexed team, string rewardName, uint256 amount);
    event RewardClaimed(address indexed team, uint256 totalReward, string rewardName);
    event LeagueClosed(address indexed commissioner, uint256 finalBalance);
    event FeePaid(address indexed league, address indexed receiver, uint256 amount);
    event DepositedToVault(address indexed vault, uint256 amount);
    event WithdrawnFromVault(address indexed vault, uint256 result);

    string public name;
    SeasonData[] public seasons;
    address[] public allTeams;
    mapping(address => RewardData[]) public teamRewards;
    uint256 public totalClaimableRewards;

    mapping(string => bool) public teamNameExists;
    mapping(address => bool) public teamWalletExists;
    mapping(address => string) public teamName;

    address[] public activeVaults;
    mapping(address => bool) public vaultActive;

    modifier onlyActive() {
        require(isActive(), "LEAGUE_NOT_ACTIVE");
        _;
    }

    constructor(string memory _leagueName, uint256 _dues, string memory _teamName, address _commissioner) {
        require(_commissioner != address(0), "INVALID_COMMISSIONER");
        require(!_compareStrings(_leagueName, ''), "INVALID_LEAGUE_NAME");
        require(!_compareStrings(_teamName, ''), "INVALID_TEAM_NAME");
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
        emit LeagueInitialized(name, _commissioner, _dues);
    }

    function totalLeagueBalance() public view returns (uint256) {
        return cashBalance() + totalVaultBalance();
    }

    function cashBalance() public view returns (uint256) {
        return IERC20(USDC).balanceOf(address(this));
    }

    function totalVaultBalance() public view returns (uint256) {
        uint256 total;
        for (uint256 i = 0; i < activeVaults.length; i++) {
            total += balanceInVault(activeVaults[i]);
        }
        return total;
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
        emit CommissionerChanged(msg.sender, _commissioner);
    }

    function addTreasurer(address _treasurer) external onlyRole(COMMISSIONER_ROLE) {
        _grantRole(TREASURER_ROLE, _treasurer);
        emit TreasurerAdded(_treasurer);
    }

    function removeTreasurer(address _treasurer) external onlyRole(COMMISSIONER_ROLE) {
        _revokeRole(TREASURER_ROLE, _treasurer);
        emit TreasurerRemoved(_treasurer);
    }

    function createSeason(uint256 _dues) public onlyRole(COMMISSIONER_ROLE) {
        uint256 fee = ILeagueFactory(FACTORY).seasonCreationFee();
        require(_dues >= fee, "DUES_TOO_LOW");
        seasons.push(SeasonData({dues: _dues, teams: new address[](0)}));
        joinSeason(teamName[msg.sender]);
        if (fee > 0) {
            IERC20(USDC).safeTransfer(ILeagueFactory(FACTORY).owner(), fee);
            emit FeePaid(address(this), ILeagueFactory(FACTORY).owner(), fee);
        }
        emit SeasonCreated(seasons.length - 1, _dues);
    }

    function _compareStrings(string memory _a, string memory _b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
    }

    function joinSeason(string memory _teamName) public onlyActive {
        require(!_compareStrings(_teamName, ''), "INVALID_TEAM_NAME");
        require(!isTeamActive(msg.sender), "TEAM_ALREADY_JOINED");
        if (teamNameExists[_teamName]) {
            require(_compareStrings(teamName[msg.sender], _teamName), "TEAM_NAME_MISMATCH");
        } else if (teamWalletExists[msg.sender]) {
            require(_compareStrings(teamName[msg.sender], _teamName), "TEAM_NAME_MISMATCH");
        } else {
            teamNameExists[_teamName] = true;
            teamWalletExists[msg.sender] = true;
            teamName[msg.sender] = _teamName;
            allTeams.push(msg.sender);
        }
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), currentSeason().dues);
        seasons[seasons.length - 1].teams.push(msg.sender);
        emit JoinedSeason(msg.sender, _teamName, seasons.length - 1);
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
                IERC20(USDC).safeTransfer(_team, currentSeason().dues);
                break;
            }
        }
        emit TeamRemoved(_team, seasons.length - 1);
    }

    function closeLeague() external onlyRole(COMMISSIONER_ROLE) {
        for (uint256 i = 0; i < activeVaults.length; i++) {
            withdrawFromVault(activeVaults[i], IERC20(activeVaults[i]).balanceOf(address(this)));
        }
        IERC20(USDC).safeTransfer(msg.sender, IERC20(USDC).balanceOf(address(this)));
        ILeagueFactory(FACTORY).removeLeague();
        emit LeagueClosed(msg.sender, IERC20(USDC).balanceOf(address(this)));
    }

    function allocateReward(address _team, string memory _name, uint256 _amount) external onlyRole(COMMISSIONER_ROLE) {
        require(isTeamActive(_team), "TEAM_NOT_IN_SEASON");
        totalClaimableRewards += _amount;
        require(totalClaimableRewards <= cashBalance(), "INSUFFICIENT_CASH_BALANCE");
        teamRewards[_team].push(RewardData({name: _name, amount: _amount}));
        emit RewardAllocated(_team, _name, _amount);
    }

    function claimReward(string memory imageURLs) external {
        RewardData[] storage rewards = teamRewards[msg.sender];
        require(rewards.length > 0, "NO_REWARDS");
        string memory rewardName = rewards[rewards.length - 1].name;
        uint256 amount = rewards[rewards.length - 1].amount;
        ILeagueRewardNFT(ILeagueFactory(FACTORY).leagueRewardNFT()).mintReward(
            msg.sender, name, teamName[msg.sender], rewardName, amount, imageURLs
        );
        emit RewardClaimed(msg.sender, amount, rewardName);
        teamRewards[msg.sender].pop();
        if (amount > 0) {
            totalClaimableRewards -= amount;
            IERC20(USDC).safeTransfer(msg.sender, amount);
        }
    }

    function depositToVault(address _vault, uint256 _amount) external onlyRole(TREASURER_ROLE) {
        require(ILeagueFactory(FACTORY).isVault(_vault), "NOT_VAULT");
        require(_amount <= (cashBalance() - totalClaimableRewards), "INSUFFICIENT_CASH_BALANCE");
        IERC20(USDC).forceApprove(_vault, _amount);
        IERC4626(_vault).deposit(_amount, address(this));
        if (!vaultActive[_vault]) {
            activeVaults.push(_vault);
            vaultActive[_vault] = true;
        }
        emit DepositedToVault(_vault, _amount);
    }

    function withdrawFromVault(address _vault, uint256 _shares) public onlyRole(TREASURER_ROLE) {
        require(_shares <= IERC20(_vault).balanceOf(address(this)), "INSUFFICIENT_VAULT_BALANCE");
        uint256 result = IERC4626(_vault).redeem(_shares, address(this), address(this));
        if (IERC20(_vault).balanceOf(address(this)) == 0) {
            vaultActive[_vault] = false;
            for (uint256 i = 0; i < activeVaults.length; i++) {
                if (activeVaults[i] == _vault) {
                    activeVaults[i] = activeVaults[activeVaults.length - 1];
                    activeVaults.pop();
                    break;
                }
            }
        }
        emit WithdrawnFromVault(_vault, result);
    }

    function balanceInVault(address _vault) public view returns (uint256) {
        return IERC4626(_vault).convertToAssets(IERC20(_vault).balanceOf(address(this)));
    }
}
