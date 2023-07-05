// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IRewardRouterV2 {
    function feeClpTracker() external view returns (address);
    function stakedClpTracker() external view returns (address);
}
