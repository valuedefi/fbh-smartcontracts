// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/ICappedMintableBurnableERC20.sol";

contract HopesToFbhBridge is Ownable {
    address public fbh;

    uint256 public startReleaseTime;
    uint256[] public totalBurned;
    uint256 public totalMinted;

    uint256[] public initialMigrationRate;
    uint256 public weeklyHalvingRate;

    mapping(uint256 => mapping(address => bool)) private _status;

    mapping(bytes32 => bool) public txReceipt; // tx_hash => claimed?

    mapping(address => bool) public authorities;

    event Migrate(address indexed account, uint256 indexed id, uint256 hopeAmount, uint256 fbhAmount);

    modifier isAuthorised() {
        require(authorities[msg.sender], "!authorised");
        _;
    }

    constructor(address _fbh, uint256 _startReleaseTime) {
        fbh = _fbh;
        startReleaseTime = _startReleaseTime;
        totalBurned = [0, 0];
        initialMigrationRate = [7040, 276]; // 1 HOPE = 0.00704 FBH & 1 HOPE-P = 0.000276 FBH
        weeklyHalvingRate = 500; // 5%
        authorities[msg.sender] = true;
    }

    function addAuthority(address authority) external onlyOwner {
        authorities[authority] = true;
    }

    function removeAuthority(address authority) external onlyOwner {
        authorities[authority] = false;
    }

    function passedWeeks() public view returns (uint256) {
        uint256 _startReleaseTime = startReleaseTime;
        if (block.timestamp < startReleaseTime) return 0;
        return (block.timestamp - _startReleaseTime) / (7 days);
    }

    function migrateRate(uint256 _id) public view returns (uint256) {
        uint256 _rate = initialMigrationRate[_id];
        uint256 _weeks = passedWeeks();
        if (_weeks == 0) return _rate;
        uint256 _totalHalvingRate = _weeks * weeklyHalvingRate;
        if (_totalHalvingRate >= 10000) return 0;
        return _rate * (10000 - _totalHalvingRate) / 10000;
    }

    function getMigrateAmount(uint256 _id, uint256 _hopeAmount) external view returns (uint256) {
        return _hopeAmount * migrateRate(_id) / 1000000;
    }

    function migrate(address _account, uint256 _id, uint256 _hopeAmount, bytes32 _tx) external isAuthorised {
        require(block.timestamp >= startReleaseTime, "migration not opened yet");
        uint256 _rate = migrateRate(_id);
        require(_rate > 0, "zero rate");
        require(!txReceipt[_tx], "already migrated");
        txReceipt[_tx] = true;
        uint256 _mintAmount = _hopeAmount * _rate / 1000000;
        ICappedMintableBurnableERC20(fbh).mint(_account, _mintAmount);
        totalBurned[_id] += _hopeAmount;
        totalMinted += _mintAmount;
        emit Migrate(_msgSender(), _id, _hopeAmount, _mintAmount);
    }

    function setStartReleaseTime(uint256 _startReleaseTime) external onlyOwner {
        require(_startReleaseTime > startReleaseTime, "cant set _startReleaseTime to lower value");
        startReleaseTime = _startReleaseTime;
    }

    function setWeeklyHalvingRate(uint256 _weeklyHalvingRate) external onlyOwner {
        require(_weeklyHalvingRate <= 2000, "too high"); // <= 20%
        weeklyHalvingRate = _weeklyHalvingRate;
    }

    /* ========== EMERGENCY ========== */

    function governanceRecoverUnsupported(IERC20 _token) external onlyOwner {
        _token.transfer(owner(), _token.balanceOf(address(this)));
    }
}
