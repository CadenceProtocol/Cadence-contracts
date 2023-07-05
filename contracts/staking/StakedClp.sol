// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";

import "../core/interfaces/IClpManager.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardTracker.sol";

import "../csr/interfaces/ITurnstile.sol";

// provide a way to transfer staked CLP tokens by unstaking from the sender
// and staking for the receiver
// tests in RewardRouterV2.js
contract StakedClp {
    using SafeMath for uint256;

    string public constant name = "StakedClp";
    string public constant symbol = "sCLP";
    uint8 public constant decimals = 18;

    address public clp;
    IClpManager public clpManager;
    address public stakedClpTracker;
    address public feeClpTracker;

    mapping(address => mapping(address => uint256)) public allowances;

    ITurnstile public constant TURNSTILE =
        ITurnstile(0xEcf044C5B4b867CFda001101c617eCd347095B44);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(
        address _clp,
        IClpManager _clpManager,
        address _stakedClpTracker,
        address _feeClpTracker
    ) public {
        clp = _clp;
        clpManager = _clpManager;
        stakedClpTracker = _stakedClpTracker;
        feeClpTracker = _feeClpTracker;

        TURNSTILE.register(tx.origin);
    }

    function allowance(
        address _owner,
        address _spender
    ) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(
        address _spender,
        uint256 _amount
    ) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(
            _amount,
            "StakedClp: transfer amount exceeds allowance"
        );
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function balanceOf(address _account) external view returns (uint256) {
        return IRewardTracker(feeClpTracker).depositBalances(_account, clp);
    }

    function totalSupply() external view returns (uint256) {
        return IERC20(stakedClpTracker).totalSupply();
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        require(
            _owner != address(0),
            "StakedClp: approve from the zero address"
        );
        require(
            _spender != address(0),
            "StakedClp: approve to the zero address"
        );

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private {
        require(
            _sender != address(0),
            "StakedClp: transfer from the zero address"
        );
        require(
            _recipient != address(0),
            "StakedClp: transfer to the zero address"
        );

        require(
            clpManager.lastAddedAt(_sender).add(
                clpManager.cooldownDuration()
            ) <= block.timestamp,
            "StakedClp: cooldown duration not yet passed"
        );

        IRewardTracker(stakedClpTracker).unstakeForAccount(
            _sender,
            feeClpTracker,
            _amount,
            _sender
        );
        IRewardTracker(feeClpTracker).unstakeForAccount(
            _sender,
            clp,
            _amount,
            _sender
        );

        IRewardTracker(feeClpTracker).stakeForAccount(
            _sender,
            _recipient,
            clp,
            _amount
        );
        IRewardTracker(stakedClpTracker).stakeForAccount(
            _recipient,
            _recipient,
            feeClpTracker,
            _amount
        );
    }
}
