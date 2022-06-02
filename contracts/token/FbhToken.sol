// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FbhToken is ERC20Capped, Ownable {
    using SafeMath for uint256;

    uint256 private constant CAP = 21000000 ether;

    mapping(address => uint256) public minterCap;

    /* ========== EVENTS ========== */

    event MinterCapUpdate(address indexed account, uint256 cap);

    /* ========== Modifiers =============== */

    modifier onlyMinter() {
        require(minterCap[msg.sender] > 0, "!minter");
        _;
    }

    /* ========== GOVERNANCE ========== */

    constructor() ERC20("Firebird Hyber", "FBH") ERC20Capped(CAP) {
        _mint(msg.sender, 400000 ether); // for initial liquidity deployment
    }

    function setMinterCap(address _account, uint256 _minterCap) external onlyOwner {
        require(_account != address(0), "zero");
        minterCap[_account] = _minterCap;
        emit MinterCapUpdate(_account, _minterCap);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function mint(address _recipient, uint256 _amount) public onlyMinter {
        minterCap[msg.sender] -= _amount;
        _mint(_recipient, _amount);
    }

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }

    function burnFrom(address _account, uint256 _amount) external {
        _approve(_account, msg.sender, allowance(_account, msg.sender) - _amount);
        _burn(_account, _amount);
    }

    /* ========== EMERGENCY ========== */

    function governanceRecoverUnsupported(IERC20 _token) external onlyOwner {
        _token.transfer(owner(), _token.balanceOf(address(this)));
    }
}
