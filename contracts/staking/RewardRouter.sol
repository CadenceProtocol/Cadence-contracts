// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IClpManager.sol";
import "../access/Governable.sol";

contract RewardRouter is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public cad;
    address public esCad;
    address public bnCad;

    address public clp; // CAD Liquidity Provider token

    address public stakedCadTracker;
    address public bonusCadTracker;
    address public feeCadTracker;

    address public stakedClpTracker;
    address public feeClpTracker;

    address public clpManager;

    event StakeCad(address account, uint256 amount);
    event UnstakeCad(address account, uint256 amount);

    event StakeClp(address account, uint256 amount);
    event UnstakeClp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _cad,
        address _esCad,
        address _bnCad,
        address _clp,
        address _stakedCadTracker,
        address _bonusCadTracker,
        address _feeCadTracker,
        address _feeClpTracker,
        address _stakedClpTracker,
        address _clpManager
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;

        cad = _cad;
        esCad = _esCad;
        bnCad = _bnCad;

        clp = _clp;

        stakedCadTracker = _stakedCadTracker;
        bonusCadTracker = _bonusCadTracker;
        feeCadTracker = _feeCadTracker;

        feeClpTracker = _feeClpTracker;
        stakedClpTracker = _stakedClpTracker;

        clpManager = _clpManager;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeCadForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _cad = cad;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeCad(msg.sender, _accounts[i], _cad, _amounts[i]);
        }
    }

    function stakeCadForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeCad(msg.sender, _account, cad, _amount);
    }

    function stakeCad(uint256 _amount) external nonReentrant {
        _stakeCad(msg.sender, msg.sender, cad, _amount);
    }

    function stakeEsCad(uint256 _amount) external nonReentrant {
        _stakeCad(msg.sender, msg.sender, esCad, _amount);
    }

    function unstakeCad(uint256 _amount) external nonReentrant {
        _unstakeCad(msg.sender, cad, _amount);
    }

    function unstakeEsCad(uint256 _amount) external nonReentrant {
        _unstakeCad(msg.sender, esCad, _amount);
    }

    function mintAndStakeClp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minClp) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 clpAmount = IClpManager(clpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdg, _minClp);
        IRewardTracker(feeClpTracker).stakeForAccount(account, account, clp, clpAmount);
        IRewardTracker(stakedClpTracker).stakeForAccount(account, account, feeClpTracker, clpAmount);

        emit StakeClp(account, clpAmount);

        return clpAmount;
    }

    function mintAndStakeClpETH(uint256 _minUsdg, uint256 _minClp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(clpManager, msg.value);

        address account = msg.sender;
        uint256 clpAmount = IClpManager(clpManager).addLiquidityForAccount(address(this), account, weth, msg.value, _minUsdg, _minClp);

        IRewardTracker(feeClpTracker).stakeForAccount(account, account, clp, clpAmount);
        IRewardTracker(stakedClpTracker).stakeForAccount(account, account, feeClpTracker, clpAmount);

        emit StakeClp(account, clpAmount);

        return clpAmount;
    }

    function unstakeAndRedeemClp(address _tokenOut, uint256 _clpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        require(_clpAmount > 0, "RewardRouter: invalid _clpAmount");

        address account = msg.sender;
        IRewardTracker(stakedClpTracker).unstakeForAccount(account, feeClpTracker, _clpAmount, account);
        IRewardTracker(feeClpTracker).unstakeForAccount(account, clp, _clpAmount, account);
        uint256 amountOut = IClpManager(clpManager).removeLiquidityForAccount(account, _tokenOut, _clpAmount, _minOut, _receiver);

        emit UnstakeClp(account, _clpAmount);

        return amountOut;
    }

    function unstakeAndRedeemClpETH(uint256 _clpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_clpAmount > 0, "RewardRouter: invalid _clpAmount");

        address account = msg.sender;
        IRewardTracker(stakedClpTracker).unstakeForAccount(account, feeClpTracker, _clpAmount, account);
        IRewardTracker(feeClpTracker).unstakeForAccount(account, clp, _clpAmount, account);
        uint256 amountOut = IClpManager(clpManager).removeLiquidityForAccount(account, weth, _clpAmount, _minOut, address(this));

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeClp(account, _clpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeCadTracker).claimForAccount(account, account);
        IRewardTracker(feeClpTracker).claimForAccount(account, account);

        IRewardTracker(stakedCadTracker).claimForAccount(account, account);
        IRewardTracker(stakedClpTracker).claimForAccount(account, account);
    }

    function claimEsCad() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedCadTracker).claimForAccount(account, account);
        IRewardTracker(stakedClpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeCadTracker).claimForAccount(account, account);
        IRewardTracker(feeClpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function _compound(address _account) private {
        _compoundCad(_account);
        _compoundClp(_account);
    }

    function _compoundCad(address _account) private {
        uint256 esCadAmount = IRewardTracker(stakedCadTracker).claimForAccount(_account, _account);
        if (esCadAmount > 0) {
            _stakeCad(_account, _account, esCad, esCadAmount);
        }

        uint256 bnCadAmount = IRewardTracker(bonusCadTracker).claimForAccount(_account, _account);
        if (bnCadAmount > 0) {
            IRewardTracker(feeCadTracker).stakeForAccount(_account, _account, bnCad, bnCadAmount);
        }
    }

    function _compoundClp(address _account) private {
        uint256 esCadAmount = IRewardTracker(stakedClpTracker).claimForAccount(_account, _account);
        if (esCadAmount > 0) {
            _stakeCad(_account, _account, esCad, esCadAmount);
        }
    }

    function _stakeCad(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedCadTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusCadTracker).stakeForAccount(_account, _account, stakedCadTracker, _amount);
        IRewardTracker(feeCadTracker).stakeForAccount(_account, _account, bonusCadTracker, _amount);

        emit StakeCad(_account, _amount);
    }

    function _unstakeCad(address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedCadTracker).stakedAmounts(_account);

        IRewardTracker(feeCadTracker).unstakeForAccount(_account, bonusCadTracker, _amount, _account);
        IRewardTracker(bonusCadTracker).unstakeForAccount(_account, stakedCadTracker, _amount, _account);
        IRewardTracker(stakedCadTracker).unstakeForAccount(_account, _token, _amount, _account);

        uint256 bnCadAmount = IRewardTracker(bonusCadTracker).claimForAccount(_account, _account);
        if (bnCadAmount > 0) {
            IRewardTracker(feeCadTracker).stakeForAccount(_account, _account, bnCad, bnCadAmount);
        }

        uint256 stakedBnCad = IRewardTracker(feeCadTracker).depositBalances(_account, bnCad);
        if (stakedBnCad > 0) {
            uint256 reductionAmount = stakedBnCad.mul(_amount).div(balance);
            IRewardTracker(feeCadTracker).unstakeForAccount(_account, bnCad, reductionAmount, _account);
            IMintable(bnCad).burn(_account, reductionAmount);
        }

        emit UnstakeCad(_account, _amount);
    }
}
