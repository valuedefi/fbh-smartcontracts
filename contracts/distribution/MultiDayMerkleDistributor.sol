// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IMultiDayMerkleDistributor.sol";

// Support Multi Snapshot
// To generate MerkleRoot:
// ts-node scripts/distribution/generate-merkle-root.ts --input scripts/distribution/example.json
contract MultiDayMerkleDistributor is IMultiDayMerkleDistributor, ReentrancyGuard, Pausable, Ownable {
    address public immutable override token;
    mapping(uint256 => bytes32) private merkleRoot_;

    // This is a packed array of booleans.
    mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMap;

    mapping(address => bool) public blacklisted; // if the snapshot is wrong we need to block the account to receive token

    mapping(address => bool) public authorities;

    constructor(address token_) {
        token = token_;
        authorities[msg.sender] = true;
    }

    modifier isAuthorised() {
        require(authorities[msg.sender], "!authorised");
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function merkleRoot(uint256 day) external override view returns (bytes32) {
        return merkleRoot_[day];
    }

    function addAuthority(address authority) external onlyOwner {
        authorities[authority] = true;
    }

    function removeAuthority(address authority) external onlyOwner {
        authorities[authority] = false;
    }

    function setBlacklisted(address _account, bool _status) external onlyOwner {
        blacklisted[_account] = _status;
    }

    function isClaimed(uint256 day, uint256 index) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[day][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 day, uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[day][claimedWordIndex] = claimedBitMap[day][claimedWordIndex] | (1 << claimedBitIndex);
    }

    function setMerkleRoot(uint256 day, bytes32 _merkleRoot) external override isAuthorised {
        merkleRoot_[day] = _merkleRoot;
    }

    function _claim(uint256 day, uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) internal {
        require(!isClaimed(day, index), "MerkleDistributor: Drop already claimed.");
        require(!blacklisted[account], "MerkleDistributor: Account is blocked.");

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot_[day], node), "MerkleDistributor: Invalid proof.");

        // Mark it claimed and send the token.
        _setClaimed(day, index);
        require(IERC20(token).transfer(account, amount), "MerkleDistributor: Transfer failed.");

        emit Claimed(day, index, account, amount);
    }

    function claim(uint256 day, uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external override nonReentrant whenNotPaused {
        _claim(day, index, account, amount, merkleProof);
    }

    function claimMultiDay(uint256[] calldata day, uint256[] calldata index, address account, uint256[] calldata amount, bytes32[][] calldata merkleProof) external override nonReentrant whenNotPaused {
        uint256 _length = day.length;
        require(index.length == _length, "index length mismatch");
        require(amount.length == _length, "amount length mismatch");
        require(merkleProof.length == _length, "merkleProof length mismatch");
        for (uint256 i = 0; i < _length; i++) {
            _claim(day[i], index[i], account, amount[i], merkleProof[i]);
        }
    }

    /* ========== EMERGENCY ========== */

    function governanceRecoverUnsupported(IERC20 _token) external onlyOwner {
        _token.transfer(owner(), _token.balanceOf(address(this)));
    }
}
