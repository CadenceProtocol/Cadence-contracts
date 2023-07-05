// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IPositionRouterCallbackReceiver {
    function cadPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external;
}
