// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardRouterV2.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IClpManager.sol";
import "../access/Governable.sol";

contract RewardRouterV2 is IRewardRouterV2, ReentrancyGuard, Governable {
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

    address public override stakedClpTracker;
    address public override feeClpTracker;

    address public clpManager;

    address public cadVester;
    address public clpVester;

    mapping(address => address) public pendingReceivers;

    event StakeCad(address account, address token, uint256 amount);
    event UnstakeCad(address account, address token, uint256 amount);

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
        address _clpManager,
        address _cadVester,
        address _clpVester
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

        cadVester = _cadVester;
        clpVester = _clpVester;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeCadForAccount(
        address[] memory _accounts,
        uint256[] memory _amounts
    ) external nonReentrant onlyGov {
        address _cad = cad;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeCad(msg.sender, _accounts[i], _cad, _amounts[i]);
        }
    }

    function stakeCadForAccount(
        address _account,
        uint256 _amount
    ) external nonReentrant onlyGov {
        _stakeCad(msg.sender, _account, cad, _amount);
    }

    function stakeCad(uint256 _amount) external nonReentrant {
        _stakeCad(msg.sender, msg.sender, cad, _amount);
    }

    function stakeEsCad(uint256 _amount) external nonReentrant {
        _stakeCad(msg.sender, msg.sender, esCad, _amount);
    }

    function unstakeCad(uint256 _amount) external nonReentrant {
        _unstakeCad(msg.sender, cad, _amount, true);
    }

    function unstakeEsCad(uint256 _amount) external nonReentrant {
        _unstakeCad(msg.sender, esCad, _amount, true);
    }

    function mintAndStakeClp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minClp
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 clpAmount = IClpManager(clpManager).addLiquidityForAccount(
            account,
            account,
            _token,
            _amount,
            _minUsdg,
            _minClp
        );
        IRewardTracker(feeClpTracker).stakeForAccount(
            account,
            account,
            clp,
            clpAmount
        );
        IRewardTracker(stakedClpTracker).stakeForAccount(
            account,
            account,
            feeClpTracker,
            clpAmount
        );

        emit StakeClp(account, clpAmount);

        return clpAmount;
    }

    function mintAndStakeClpETH(
        uint256 _minUsdg,
        uint256 _minClp
    ) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(clpManager, msg.value);

        address account = msg.sender;
        uint256 clpAmount = IClpManager(clpManager).addLiquidityForAccount(
            address(this),
            account,
            weth,
            msg.value,
            _minUsdg,
            _minClp
        );

        IRewardTracker(feeClpTracker).stakeForAccount(
            account,
            account,
            clp,
            clpAmount
        );
        IRewardTracker(stakedClpTracker).stakeForAccount(
            account,
            account,
            feeClpTracker,
            clpAmount
        );

        emit StakeClp(account, clpAmount);

        return clpAmount;
    }

    function unstakeAndRedeemClp(
        address _tokenOut,
        uint256 _clpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_clpAmount > 0, "RewardRouter: invalid _clpAmount");

        address account = msg.sender;
        IRewardTracker(stakedClpTracker).unstakeForAccount(
            account,
            feeClpTracker,
            _clpAmount,
            account
        );
        IRewardTracker(feeClpTracker).unstakeForAccount(
            account,
            clp,
            _clpAmount,
            account
        );
        uint256 amountOut = IClpManager(clpManager).removeLiquidityForAccount(
            account,
            _tokenOut,
            _clpAmount,
            _minOut,
            _receiver
        );

        emit UnstakeClp(account, _clpAmount);

        return amountOut;
    }

    function unstakeAndRedeemClpETH(
        uint256 _clpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        require(_clpAmount > 0, "RewardRouter: invalid _clpAmount");

        address account = msg.sender;
        IRewardTracker(stakedClpTracker).unstakeForAccount(
            account,
            feeClpTracker,
            _clpAmount,
            account
        );
        IRewardTracker(feeClpTracker).unstakeForAccount(
            account,
            clp,
            _clpAmount,
            account
        );
        uint256 amountOut = IClpManager(clpManager).removeLiquidityForAccount(
            account,
            weth,
            _clpAmount,
            _minOut,
            address(this)
        );

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

    function compoundForAccount(
        address _account
    ) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimCad,
        bool _shouldStakeCad,
        bool _shouldClaimEsCad,
        bool _shouldStakeEsCad,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 cadAmount = 0;
        if (_shouldClaimCad) {
            uint256 cadAmount0 = IVester(cadVester).claimForAccount(
                account,
                account
            );
            uint256 cadAmount1 = IVester(clpVester).claimForAccount(
                account,
                account
            );
            cadAmount = cadAmount0.add(cadAmount1);
        }

        if (_shouldStakeCad && cadAmount > 0) {
            _stakeCad(account, account, cad, cadAmount);
        }

        uint256 esCadAmount = 0;
        if (_shouldClaimEsCad) {
            uint256 esCadAmount0 = IRewardTracker(stakedCadTracker)
                .claimForAccount(account, account);
            uint256 esCadAmount1 = IRewardTracker(stakedClpTracker)
                .claimForAccount(account, account);
            esCadAmount = esCadAmount0.add(esCadAmount1);
        }

        if (_shouldStakeEsCad && esCadAmount > 0) {
            _stakeCad(account, account, esCad, esCadAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnCadAmount = IRewardTracker(bonusCadTracker)
                .claimForAccount(account, account);
            if (bnCadAmount > 0) {
                IRewardTracker(feeCadTracker).stakeForAccount(
                    account,
                    account,
                    bnCad,
                    bnCadAmount
                );
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 weth0 = IRewardTracker(feeCadTracker).claimForAccount(
                    account,
                    address(this)
                );
                uint256 weth1 = IRewardTracker(feeClpTracker).claimForAccount(
                    account,
                    address(this)
                );

                uint256 wethAmount = weth0.add(weth1);
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeCadTracker).claimForAccount(account, account);
                IRewardTracker(feeClpTracker).claimForAccount(account, account);
            }
        }
    }

    function batchCompoundForAccounts(
        address[] memory _accounts
    ) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    // the _validateReceiver function checks that the averageStakedAmounts and cumulativeRewards
    // values of an account are zero, this is to help ensure that vesting calculations can be
    // done correctly
    // averageStakedAmounts and cumulativeRewards are updated if the claimable reward for an account
    // is more than zero
    // it is possible for multiple transfers to be sent into a single account, using signalTransfer and
    // acceptTransfer, if those values have not been updated yet
    // for CLP transfers it is also possible to transfer CLP into an account using the StakedClp contract
    function signalTransfer(address _receiver) external nonReentrant {
        require(
            IERC20(cadVester).balanceOf(msg.sender) == 0,
            "RewardRouter: sender has vested tokens"
        );
        require(
            IERC20(clpVester).balanceOf(msg.sender) == 0,
            "RewardRouter: sender has vested tokens"
        );

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(
            IERC20(cadVester).balanceOf(_sender) == 0,
            "RewardRouter: sender has vested tokens"
        );
        require(
            IERC20(clpVester).balanceOf(_sender) == 0,
            "RewardRouter: sender has vested tokens"
        );

        address receiver = msg.sender;
        require(
            pendingReceivers[_sender] == receiver,
            "RewardRouter: transfer not signalled"
        );
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedCad = IRewardTracker(stakedCadTracker).depositBalances(
            _sender,
            cad
        );
        if (stakedCad > 0) {
            _unstakeCad(_sender, cad, stakedCad, false);
            _stakeCad(_sender, receiver, cad, stakedCad);
        }

        uint256 stakedEsCad = IRewardTracker(stakedCadTracker).depositBalances(
            _sender,
            esCad
        );
        if (stakedEsCad > 0) {
            _unstakeCad(_sender, esCad, stakedEsCad, false);
            _stakeCad(_sender, receiver, esCad, stakedEsCad);
        }

        uint256 stakedBnCad = IRewardTracker(feeCadTracker).depositBalances(
            _sender,
            bnCad
        );
        if (stakedBnCad > 0) {
            IRewardTracker(feeCadTracker).unstakeForAccount(
                _sender,
                bnCad,
                stakedBnCad,
                _sender
            );
            IRewardTracker(feeCadTracker).stakeForAccount(
                _sender,
                receiver,
                bnCad,
                stakedBnCad
            );
        }

        uint256 esCadBalance = IERC20(esCad).balanceOf(_sender);
        if (esCadBalance > 0) {
            IERC20(esCad).transferFrom(_sender, receiver, esCadBalance);
        }

        uint256 clpAmount = IRewardTracker(feeClpTracker).depositBalances(
            _sender,
            clp
        );
        if (clpAmount > 0) {
            IRewardTracker(stakedClpTracker).unstakeForAccount(
                _sender,
                feeClpTracker,
                clpAmount,
                _sender
            );
            IRewardTracker(feeClpTracker).unstakeForAccount(
                _sender,
                clp,
                clpAmount,
                _sender
            );

            IRewardTracker(feeClpTracker).stakeForAccount(
                _sender,
                receiver,
                clp,
                clpAmount
            );
            IRewardTracker(stakedClpTracker).stakeForAccount(
                receiver,
                receiver,
                feeClpTracker,
                clpAmount
            );
        }

        IVester(cadVester).transferStakeValues(_sender, receiver);
        IVester(clpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(
            IRewardTracker(stakedCadTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: stakedCadTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedCadTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedCadTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(bonusCadTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: bonusCadTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(bonusCadTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: bonusCadTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feeCadTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feeCadTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feeCadTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feeCadTracker.cumulativeRewards > 0"
        );

        require(
            IVester(cadVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: cadVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(cadVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: cadVester.transferredCumulativeRewards > 0"
        );

        require(
            IRewardTracker(stakedClpTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: stakedClpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedClpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedClpTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feeClpTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feeClpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feeClpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feeClpTracker.cumulativeRewards > 0"
        );

        require(
            IVester(clpVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: cadVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(clpVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: cadVester.transferredCumulativeRewards > 0"
        );

        require(
            IERC20(cadVester).balanceOf(_receiver) == 0,
            "RewardRouter: cadVester.balance > 0"
        );
        require(
            IERC20(clpVester).balanceOf(_receiver) == 0,
            "RewardRouter: clpVester.balance > 0"
        );
    }

    function _compound(address _account) private {
        _compoundCad(_account);
        _compoundClp(_account);
    }

    function _compoundCad(address _account) private {
        uint256 esCadAmount = IRewardTracker(stakedCadTracker).claimForAccount(
            _account,
            _account
        );
        if (esCadAmount > 0) {
            _stakeCad(_account, _account, esCad, esCadAmount);
        }

        uint256 bnCadAmount = IRewardTracker(bonusCadTracker).claimForAccount(
            _account,
            _account
        );
        if (bnCadAmount > 0) {
            IRewardTracker(feeCadTracker).stakeForAccount(
                _account,
                _account,
                bnCad,
                bnCadAmount
            );
        }
    }

    function _compoundClp(address _account) private {
        uint256 esCadAmount = IRewardTracker(stakedClpTracker).claimForAccount(
            _account,
            _account
        );
        if (esCadAmount > 0) {
            _stakeCad(_account, _account, esCad, esCadAmount);
        }
    }

    function _stakeCad(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedCadTracker).stakeForAccount(
            _fundingAccount,
            _account,
            _token,
            _amount
        );
        IRewardTracker(bonusCadTracker).stakeForAccount(
            _account,
            _account,
            stakedCadTracker,
            _amount
        );
        IRewardTracker(feeCadTracker).stakeForAccount(
            _account,
            _account,
            bonusCadTracker,
            _amount
        );

        emit StakeCad(_account, _token, _amount);
    }

    function _unstakeCad(
        address _account,
        address _token,
        uint256 _amount,
        bool _shouldReduceBnCad
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedCadTracker).stakedAmounts(
            _account
        );

        IRewardTracker(feeCadTracker).unstakeForAccount(
            _account,
            bonusCadTracker,
            _amount,
            _account
        );
        IRewardTracker(bonusCadTracker).unstakeForAccount(
            _account,
            stakedCadTracker,
            _amount,
            _account
        );
        IRewardTracker(stakedCadTracker).unstakeForAccount(
            _account,
            _token,
            _amount,
            _account
        );

        if (_shouldReduceBnCad) {
            uint256 bnCadAmount = IRewardTracker(bonusCadTracker)
                .claimForAccount(_account, _account);
            if (bnCadAmount > 0) {
                IRewardTracker(feeCadTracker).stakeForAccount(
                    _account,
                    _account,
                    bnCad,
                    bnCadAmount
                );
            }

            uint256 stakedBnCad = IRewardTracker(feeCadTracker).depositBalances(
                _account,
                bnCad
            );
            if (stakedBnCad > 0) {
                uint256 reductionAmount = stakedBnCad.mul(_amount).div(balance);
                IRewardTracker(feeCadTracker).unstakeForAccount(
                    _account,
                    bnCad,
                    reductionAmount,
                    _account
                );
                IMintable(bnCad).burn(_account, reductionAmount);
            }
        }

        emit UnstakeCad(_account, _token, _amount);
    }
}
