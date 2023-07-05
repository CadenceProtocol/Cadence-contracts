// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";

import "../core/interfaces/IClpManager.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardTracker.sol";

import "../access/Governable.sol";

// provide a way to migrate staked CLP tokens by unstaking from the sender
// and staking for the receiver
// meant for a one-time use for a specified sender
// requires the contract to be added as a handler for stakedClpTracker and feeClpTracker
contract StakedClpMigrator is Governable {
    using SafeMath for uint256;

    address public sender;
    address public clp;
    address public stakedClpTracker;
    address public feeClpTracker;
    bool public isEnabled = true;

    constructor(
        address _sender,
        address _clp,
        address _stakedClpTracker,
        address _feeClpTracker
    ) public {
        sender = _sender;
        clp = _clp;
        stakedClpTracker = _stakedClpTracker;
        feeClpTracker = _feeClpTracker;
    }

    function disable() external onlyGov {
        isEnabled = false;
    }

    function transfer(address _recipient, uint256 _amount) external onlyGov {
        _transfer(sender, _recipient, _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(isEnabled, "StakedClpMigrator: not enabled");
        require(_sender != address(0), "StakedClpMigrator: transfer from the zero address");
        require(_recipient != address(0), "StakedClpMigrator: transfer to the zero address");

        IRewardTracker(stakedClpTracker).unstakeForAccount(_sender, feeClpTracker, _amount, _sender);
        IRewardTracker(feeClpTracker).unstakeForAccount(_sender, clp, _amount, _sender);

        IRewardTracker(feeClpTracker).stakeForAccount(_sender, _recipient, clp, _amount);
        IRewardTracker(stakedClpTracker).stakeForAccount(_recipient, _recipient, feeClpTracker, _amount);
    }
}
